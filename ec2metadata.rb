require 'aws-sdk'
require 'sinatra'
require 'curb'
require 'sinatra/reloader' if development?
require 'tilt/erubis' 
require 'json'
require 'shellwords'
require 'open3'
require 'inifile'

set :bind, '0.0.0.0'
set :port, 4567


# collection of AWS profiles
# also handles knowing which is exposed
class AwsProfiles
  attr_reader :credential_source
  def initialize source='~/.aws/credentials'
    @profiles = Hash.new
    @credential_source = source
  end
  def profile name, refresh=true
    self.profiles refresh
    return @profiles[name]
  end
  def profiles refresh=true
    if refresh or @profiles.keys.length == 0
      profile_path = File.expand_path @credential_source
      aws_config = IniFile.load( profile_path )
      aws_config.each_section do |section| 
        next unless aws_config[section].keys.include?('aws_access_key_id') and aws_config[section].keys.include?('aws_secret_access_key')
        @profiles[section] = AwsProfile.new(section)
      end
    end
    @profiles.keys
  end
end

# one AWS Profile
class AwsProfile

  attr_reader :name, :current, :roles
  def initialize name
    @name = name
    @credentials = Aws::SharedCredentials.new( profile_name: @name)
    opts = {  credentials: @credentials }
    @sts = Aws::STS::Client.new(opts)
    @iam = Aws::IAM::Client.new(opts)
    @serial = nil
    @roles = []
    @current = {}
    @mfa_sts = nil
  end
  def get_serial_number
    @serial ||= @iam.list_mfa_devices.mfa_devices[0].serial_number
    @serial
  end
  def get_session_token config, serial=nil
    if config[:token_code]
      if not serial
        get_serial_number
        serial = @serial
      end
      config[:serial_number] = serial
    end
    @current = @sts.get_session_token(config).to_h[:credentials]
    @mfa_sts = Aws::STS::Client.new(  credentials: AWS::Credentials.new( @current) )
  end
  def expired?
    return ( @current[:expiration] and @current[:expiration] <= Time.now)
  end
  def expiration
    return @current[:expiration].to_s
  end
  def delete_session_token
    @current = {}
  end
  def expiration 
    if @mfa_sts and not expired?
      return @current[:expiration]
    else
      return nil
    end
  end
  def assume_role role, config={}
    config[:role_arn] = role
    config[:role_session_name] ||= 'ec2metadata-role-assumption' # todo!
    if config[:token_code] and not config[:serial_number]
      # we'll provide one for the profile
      config[:serial_number] = get_serial_number
    end
    if @mfa_sts and not expired?
      sts = @mfa_sts
    else
      sts = @sts
    end
    resp = sts.assume_role()
    @roles[ role ] = resp[:credentials]
  end
  def to_json
    { 
      name: @name,
      expiration: @current[:expiration].to_s,
      expired: expired?,
      roles: @roles
    }.to_json
  end
end

awsProfiles = AwsProfiles.new

get '/v2/profiles' do 
  content_type 'application/json'
  profiles = awsProfiles.profiles
  return profiles.to_json
end

get '/v2/profiles/:profile' do
  content_type 'application/json'
  profile = awsProfiles.profile( params[:profile] )
  #puts profile
  if profile
    profile.to_json
  else
    status 404
    { error: "No such profile '#{params[:profile]}'", valid_values: AwsProfile.profiles(false) }.to_json
  end
end

post "/v2/profiles/:profile/mfa" do
  status 500
  "unimplemented"
end


get '/v2' do
    erb :index, { layout: :main, locals: { awsProfiles: awsProfiles } }
end


# the region actually doesn't matter for STS and IAM which are global, but it's required for some calls anyway
# I suspect it still determines the service endpoint which exist in many regions
region='us-east-1'

profiles = []

refresh = false

credentials = nil

profiles = []
profile_path = File.expand_path "~/.aws/credentials" 


aws_config = IniFile.load( profile_path )
aws_config.each_section do |section| 
  required_fields = %w[ aws_access_key_id aws_secret_access_key ]
  if (aws_config[section].keys & required_fields ).length == required_fields.length
    profiles  << section
  end
end

roles = []
mfa_devices =[]
current_profile = nil

used_roles = []

sort_roles = proc { 
	  roles.sort! do |a,b|
      #$stderr.puts "Comparing:\n\t* #{a}\n\t* #{b}"
      res = nil
      if used_roles.include? a
        $stderr.puts "#{a} in used_roles (a)"
        res = -1 unless used_roles.include? b
      elsif used_roles.include? b
        $stderr.puts "#{b} in used_roles (b)"
        res = 1
      end
      unless res # one or the other is in used_roles
	      #$stderr.puts "neither #{a} or #{b} in used_roles"
        order = [
          %r|:role/admin$|,
          %r|:role/app/| ,
          %r|:role/admin/|,
          %r|:role/read/| ,
        ]
	      order.each do |r|
	        #$stderr.puts r.inspect
	        if a =~ r and b =~ r
	          #$stderr.puts "both match #{r}"
	          res = a<=>b
	        elsif a =~ r  # a comes first
	          #$stderr.puts "#{a} matches #{r}"
	          res = 1
	        elsif b =~ r  # b comes first
	          #$stderr.puts "#{b} matches #{r}"
	          res = -1
	        end  
	        break if res # we have a solution if this is the case
	      end 
	      end
	    res = a<=>b unless res # didn't match anything
      res
	  end
}

class ProfileAuthException < RuntimeError; end

profile_auth = Hash.new

discover_profile_data = proc {  |mfa,mfa_exp,list_roles|
	roles = []
  used_roles = []
  profile_auth[current_profile] = {}  if not profile_auth.keys.include? current_profile 
	mfa_devices =[]
  if current_profile
	  `aws --region us-east-1 --profile #{Shellwords.escape current_profile} iam list-mfa-devices --query MFADevices[*].SerialNumber --output text`.each_line do |line|
	    $stderr.puts "MFA Device: #{line}"
	    mfa_devices << line.strip
	  end
    if mfa =~ /^\d+$/ and mfa_exp =~ /^\d+$/
      authdata, stderr, status  = Open3.capture3( "aws sts get-session-token --profile #{Shellwords.escape current_profile} --token-code #{Shellwords.escape mfa}  --serial-number #{Shellwords.escape mfa_devices.first} --duration-seconds #{Shellwords.escape mfa_exp}" )
      raise ProfileAuthException, "#{profile_auth} #{stderr}" unless status == 0
      profile_auth[current_profile]=JSON.parse( authdata )['Credentials']
    end
    if list_roles
      puts "Looking up roles"
      role_regex=':role/(app|read|admin)'
	    `aws iam --profile #{Shellwords.escape current_profile} --region us-east-1 list-roles --query *[*].[Arn] --output text | egrep '#{role_regex}'`.lines.each do |line|
	      roles << line.strip
        puts line.strip
	    end
      sort_roles.call()
    else
      puts "Not looking up roles"
      roles = []
    end
  end
}
current_role = nil

do_assume_role = proc do |params|
  if params[:mfa] =~ /^[0-9]+$/
    mfa_str = "--serial-number #{Shellwords.escape params[:serial]} --token-code #{Shellwords.escape params[:mfa]}"
  else
    mfa_str = ""
  end
  if used_roles.include? params[:role]
    used_roles.delete params[:role]
  end
  used_roles.unshift params[:role]
  # $stderr.puts command
  if not profile_auth.keys.include? current_profile or profile_auth[current_profile].empty? 
    command = "aws --profile #{Shellwords.escape current_profile} --region us-east-1 sts assume-role --role-arn #{Shellwords.escape params[:role]} --role-session-name assumed-role #{mfa_str} --duration-seconds #{Shellwords.escape params[:duration]}"
    stdout, stderr, status = Open3.capture3( command )
  else
    command = "aws --region us-east-1 sts assume-role --role-arn #{Shellwords.escape params[:role]} --role-session-name assumed-role --duration-seconds #{Shellwords.escape params[:duration]}"
    stdout, stderr, status = Open3.capture3( 
      { 
        "AWS_SESSION_TOKEN"=>profile_auth[current_profile]['SessionToken'],
        "AWS_ACCESS_KEY_ID"=>profile_auth[current_profile]['AccessKeyId'],
        "AWS_SECRET_ACCESS_KEY"=>profile_auth[current_profile]['SecretAccessKey'],
      },
      command 
    )
  end
  result = { stdout: stdout, stderr: stderr, status: status }
  if status.exitstatus == 0 
    data = JSON.parse(stdout)
    result['data'] = data
    credentials = {
      Code: "Success", 
      LastUpdated: Time.new.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      Type: "AWS-HMAC",
      AccessKeyId: data['Credentials']['AccessKeyId'], 
      SecretAccessKey: data['Credentials']['SecretAccessKey'], 
      Token: data['Credentials']['SessionToken'], 
      Expiration: data['Credentials']['Expiration']
    }
    result['credentials'] = credentials
    current_role = params[:role]
  end
  result
end




class PerRequesterRoles 
  attr_accessor :requester_roles
  def initialize
    @requester_roles = {}
  end

  def requester_data request
    "#{request.ip}:#{request.user_agent}"
  end

  def log_requester request
    requester_id = requester_data(request)
    if @requester_roles.keys().include? requester_id
      @requester_roles[requester_id][:requests] += 1
    else
      @requester_roles[requester_id] = { requests: 1 }
    end
    return requester_id
  end  


  def dump_json
    JSON.pretty_generate @requester_roles.to_h
  end

end

requester_roles = PerRequesterRoles.new 

get %r|/latest/meta-data/iam/security-credentials/?| do
 requester_roles.log_requester request
 if current_profile
    if current_role
      current_role
    end 
  end
end

#require 'digest/sha1' # crc should be faster!
require 'zlib' 
require 'date'

get %r|/config/current| do 
    if current_role
    redirect "/config/#{current_role}", 303 
    else
    status 404
    "No role is set"
    end
end

post '/authenticate' do 
  if params['autorefresh'] == 'on'
    refresh = true
  else
    refresh = false
  end
  result = do_assume_role[params]
  if result[:status].exitstatus == 0 
    content_type 'text/json'
    redirect back, JSON.pretty_generate(result)
  else
    status 500
    content_type 'text/html'
    "<p><b>Failed to assume role:</b> <code>#{ result[:stderr] }</code></p> <p>Please use the back button on your browser to try again.</p>"
  end
end
get %r|/config/(.+)/?| do
    content_type 'text/plain'
    region = params['region'] 
    erb :config, { locals: { role: params['captures'].first, profile_auth: profile_auth[current_profile], region: params[:region] || nil  } }
end

get %r|/latest/meta-data/iam/security-credentials/(.+)| do
  requester_roles.log_requester request
  if current_profile
    if params['captures'].first == current_role
      if DateTime.parse(credentials[:Expiration]) <= DateTime.now
        if refresh
          puts do_assume_role.inspect
          results = do_assume_role.call( { duration: 3600, role: current_role, mfa: nil } )
          # provide credentials
          data = JSON.pretty_generate credentials
          content_type 'text/json'
          etag Zlib::crc32(data).to_s
          last_modified DateTime.parse( credentials[:LastUpdated] )
          data
        else
          # credentials are expired
          status 404
        end
      else
        # provide credentials
        data = JSON.pretty_generate credentials
        content_type 'text/json'
        etag Zlib::crc32(data).to_s
        last_modified DateTime.parse( credentials[:LastUpdated] )
        data
      end
    else
      status 404
    end
  end
end

get '/using-config' do 
  erb :using_config
end

get '/status' do
  status 200
  content_type 'text/json'
  JSON.pretty_generate :credentials=> credentials
end

get '/' do  
  if current_profile == nil 
    erb :main do 
      erb :profile, locals: { profiles: profiles } 
    end
  else
    sort_roles.call()
    erb :index, { layout: :main, locals: { current_role: current_role, requesters: requester_roles.requester_roles, current_profile: current_profile, mfa_devices: mfa_devices,  :roles => roles, :profile_auth => profile_auth } }
  end
end

get '/identity' do 
  content_type "application/json"
  `aws sts get-caller-identity`
end

get '/profile' do
  if current_profile
    current_profile
  else
    status 404
    "No current profile"
  end
end 

# generic metadata interface.  Post in what you want, then you can get it back just like 
# on an instance.  
meta_data = {}
get '/latest/meta-data' do
  content_type 'text/json'
  JSON.pretty_generate(meta_data)
end

post %r|/latest/meta-data/(.+)| do
  key = params[:captures][0]
  request.body.rewind
  value = request.body.read 
  if value.length == 0
    meta_data.delete key
  else
    meta_data[key] = value
  end
  status 204
end
get %r|/latest/meta-data/(.+)| do
  key = params[:captures][0]
  if meta_data[key]
    content_type 'text/plain'
    meta_data[key]
  else
    status 404
    ""
  end
end

post '/profile' do
  begin 
  if params[:profile] == "" or params[:profile] == nil
    current_profile = nil
    current_role = nil
    discover_profile_data.call( nil, nil, false )
    redirect '/', 303 
  elsif profiles.include? params[:profile]
    puts params.inspect
    current_profile = params[:profile]
    discover_profile_data.call( params[:profile_mfa], params[:profile_mfa_time], ( params[:listroles] == 'on') )
    redirect '/', 303 
  else
    status 404
    "Couldn't change profile: no such profile '#{params[:profile]}'"
  end
  rescue ProfileAuthException => e
    status 401
    content_type "text/plain"
    e.message
  end
end


if settings.environment == :development
  
  post "/expire" do
    credentials[:Expiration] = Time.new.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    content_type "text/plain"
    "Credentials expire \"now\": #{credentials[:Expiration]}"
  end

  get '/debug/profile_auth' do
      command= "aws sts get-caller-identity"
      begin
        env= {
          "AWS_SESSION_TOKEN"=>profile_auth[current_profile]['SessionToken'],
          "AWS_ACCESS_KEY_ID"=>profile_auth[current_profile]['AccessKeyId'],
          "AWS_SECRET_ACCESS_KEY"=>profile_auth[current_profile]['SecretAccessKey'],
        }
        command= "aws sts get-caller-identity"
      rescue NoMethodError
        env = {
          "PROFILE_AUTH"=>profile_auth.inspect
        }
        command= "env"
      end
      stdout, stderr, status = Open3.capture3( env, command)
      content_type "text/json"
      JSON.pretty_generate( { stdout: stdout, stderr: stderr, status: status } )
  end
  
  get '/debug' do
      sort_roles.call()
    { :mfa_devices => mfa_devices,  :roles => roles, credentials: credentials, current_role: current_role, profile_auth: profile_auth }.to_json
  end
  
  get '/debug/used_roles' do
    content_type 'text/json'
    JSON.pretty_generate( { used_roles: used_roles } )
  end
  
  get '/debug/requesters' do 
    requester_roles.dump_json
  end
  
end

  get '/ping' do
    status 200
    content_type 'text/plain'
    "pong"
  end

  get '/check' do
    checks = {}
    c = Curl::Easy.new('http://169.254.169.254/ping')
    c.timeout = 1
    content_type 'text/html'
    check = {}
    begin
      c.http_get
      check['passed'] = true
    rescue Curl::Err::CurlError
      check['passed'] = false
    end
    checks['metadata_ip'] = check
    full_result = nil
    if checks.reject {|name,results| results['passed'] }.length == 0
      status 200
      full_result = true
    else
      full_result = false
      status 500
    end
    erb :check, locals: { full_result: full_result, checks: checks }
  end

