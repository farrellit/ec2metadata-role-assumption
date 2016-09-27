#require 'aws-sdk'

`which aws`
unless $?.exitstatus == 0
  abort "Can't run without the aws command line utility to assume session token"
end

# the region actually doesn't matter for STS and IAM which are global, but it's required for some calls anyway
# I suspect it still determines the service endpoint which exist in many regions
region='us-east-1'

profiles = []

profile_path = "~/.aws/credentials"
begin 
  profile_path = File.expand_path profile_path
rescue ArgumentError=>e # docker container maybe?
  profile_path = "/code/.aws/credentials"
  ENV['HOME'] = '/code'
end

require 'inifile'
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
          %r|:role/app/| ,
          %r|:role/admin/| ,
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

discover_profile_data = proc { 
	roles = []
  used_roles = []
	mfa_devices =[]
  if current_profile
    puts "Looking up roles"
    role_regex=':role/(app|read|admin)/'
	  `aws iam --profile #{Shellwords.escape current_profile} --region us-east-1 list-roles --query *[*].[Arn] --output text | egrep '#{role_regex}'`.lines.each do |line|
	    roles << line.strip
      puts line.strip
	  end
    sort_roles.call()
	  `aws --region us-east-1 --profile #{Shellwords.escape current_profile} iam list-mfa-devices --query MFADevices[*].SerialNumber --output text`.each_line do |line|
	    $stderr.puts "MFA Device: #{line}"
	    mfa_devices << line.strip
	  end
  end
}
current_role = nil

require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis' 
require 'json'
require 'shellwords'
require 'open3'

set :bind, '0.0.0.0'
set :port, 4567

credentials = nil

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

get '/latest/meta-data/iam/security-credentials/' do
 requester_roles.log_requester request
 if current_role
    current_role
  end 
end

get %r|/latest/meta-data/iam/security-credentials/(.+)| do
  requester_roles.log_requester request
  if params['captures'].first == current_role
    content_type 'text/json'
    JSON.pretty_generate credentials
  else
    status 404
  end
end

get '/status' do
  status 200
  content_type 'text/json'
  JSON.pretty_generate :credentials=> credentials
end

post '/authenticate' do 
  if params[:mfa] =~ /^[0-9]+$/
    mfa_str = "--serial-number #{Shellwords.escape params[:serial]} --token-code #{Shellwords.escape params[:mfa]}"
  else
    mfa_str = ""
  end
  if used_roles.include? params[:role]
    used_roles.delete params[:role]
  end
  used_roles.unshift params[:role]
  command = "aws --profile #{Shellwords.escape current_profile} --region us-east-1 sts assume-role --role-arn #{Shellwords.escape params[:role]} --role-session-name assumed-role #{mfa_str} --duration-seconds #{Shellwords.escape params[:duration]}"
  $stderr.puts command
  stdout, stderr, status = Open3.capture3( command )
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
    if params.keys.include? :requester
      requester_roles.requester_roles[params[:requester]][:credentials] = credentials
      puts "Setting credentials for requester #{params[:requester]}"
    else
      puts "params: #{params.inspect}"
    end
    result['credentials'] = credentials
    current_role = params[:role]
    status 200
    content_type 'text/json'
    redirect back, JSON.pretty_generate(result)
  else
    status 500
    content_type 'text/html'
    "<p><b>Failed to assume role:</b> <code>#{ result[:stderr] }</code></p> <p>Please use the back button on your browser to try again.</p>"
  end
end

get '/' do  
  if current_profile == nil 
    erb :profile, { locals: { profiles: profiles } }
  else
    sort_roles.call()
    erb :index, { locals: { requesters: requester_roles.requester_roles, current_profile: current_profile, mfa_devices: mfa_devices,  :roles => roles } }
  end
end

get '/profile' do
  if current_profile
    current_profile
  else
    status 404
    "No current profile"
  end
end 

post '/profile' do
  if params[:profile] == "" or params[:profile] == nil
    current_profile = nil
    discover_profile_data.call
    redirect '/', 303 
  elsif profiles.include? params[:profile]
    current_profile = params[:profile]
    discover_profile_data.call
    redirect '/', 303 
  else
    status 404
    "Couldn't change profile: no such profile '#{params[:profile]}'"
  end
end

get '/debug' do
    sort_roles.call()
  { :mfa_devices => mfa_devices,  :roles => roles, credentials: credentials, current_role: current_role }.to_json
end

get '/debug/used_roles' do
  content_type 'text/json'
  JSON.pretty_generate( { used_roles: used_roles } )
end

get '/debug/requesters' do 
  requester_roles.dump_json
end
