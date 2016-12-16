#require 'aws-sdk'
require 'inifile'

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


class Profile
  attr_reader :name, :roles, :role_history, :current_role, :credentials, :mfa_devices
  def initialize name, config 
    @name = name
    @roles = []
    @session = {} 
    @role_history = []
    @current_role = nil
    @credentials = nil
    @config = config
  end
  def load_roles cache=nil
    if cache.kind_of? Array
      @roles = cache
    else
	    roles = []
	    `aws iam --profile #{Shellwords.escape @name} --region us-east-1 list-roles --query *[*].[Arn] --output text `.lines.each do |line|
	      roles << line.strip
	    end
      roles.sort
      @roles = roles
    end
  end

  def get_session_token( mfa, mfa_exp )
      @session, stderr, status  = Open3.capture3( "aws sts get-session-token --profile #{Shellwords.escape @name} --token-code #{Shellwords.escape mfa}  --serial-number #{Shellwords.escape @mfa_devices.first} --duration-seconds #{Shellwords.escape mfa_exp}" )
      raise ProfileAuthException, "#{stderr}" unless status == 0
      @session = JSON.parse( authdata )['Credentials']
  end

  def make_cache
    { roles: @roles.dup, mfa_devices: @mfa_devices.dup }
  end
  def load_mfa cache = nil
    cache ||= []
    if cache.length > 0
      @mfa_devices = cache
	  else
      @mfa_devices =[]
	    `aws --region us-east-1 --profile #{Shellwords.escape @name} iam list-mfa-devices --query MFADevices[*].SerialNumber --output text`.each_line do |line|
	      $stderr.puts "MFA Device: #{line}"
	      @mfa_devices << line.strip
      end
	  end
  end

  def discover_profile_data cache={}
    cache ||= {}
    load_mfa cache['mfa_devices']
    load_roles cache['roles']
  end

  def assume_role params
    if params[:mfa] =~ /^[0-9]+$/
      mfa_str = "--serial-number #{Shellwords.escape params[:serial]} --token-code #{Shellwords.escape params[:mfa]}"
    else
      mfa_str = ""
    end
    command = "aws --region us-east-1 sts assume-role --role-arn #{Shellwords.escape params[:role]} --role-session-name assumed-role --duration-seconds #{Shellwords.escape params[:duration]}"
    if not @credentials
      command += " --profile #{Shellwords.escape @name}" 
      env = {}
    else
      env = { 
        "AWS_SESSION_TOKEN"    => @credentials['SessionToken'],
        "AWS_ACCESS_KEY_ID"    => @credentials['AccessKeyId'],
        "AWS_SECRET_ACCESS_KEY"=> @credentials['SecretAccessKey'],
      }
    end
    stdout, stderr, status = Open3.capture3( env, command )
    result = { stdout: stdout, stderr: stderr, status: status }
    if status.exitstatus == 0
      @current_role = params[:role]
      @role_history.delete @current_role
      @role_history << @current_role
      data = JSON.parse(stdout)
      result['data'] = data
      @credentials = {
        Code: "Success", 
        LastUpdated: Time.new.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        Type: "AWS-HMAC",
        AccessKeyId: data['Credentials']['AccessKeyId'], 
        SecretAccessKey: data['Credentials']['SecretAccessKey'], 
        Token: data['Credentials']['SessionToken'], 
        Expiration: data['Credentials']['Expiration']
      }
      result['credentials'] = @credentials
    end
    return result
  end

end

class Profiles
  def initialize( path )
    @profiles = {}
    @current = nil
    @profile_path = path
    load_profiles( path )
  end
  def profile
    return nil unless @current
    @profiles[@current]
  end
  def current_profile
    @current
  end
  def set_current_profile name=nil
    if name and not @profiles.keys.include? name
      raise ArgumentError, "#{name} is not a profile ( #{@profiles.keys.join ', '} )"
    end
    @current = name
  end
  def names
    @profiles.keys
  end
  def includes?  name
    names.keys.include? name
  end
  def load_profiles( profile_path = nil, cache = {} )
    if File.exists? "/tmp/ec2_roles.json"
      File.open( "/tmp/ec2_roles.json", "r" ) do |f|
        begin
          cache = JSON.parse f.read( ) 
        rescue JSON::ParserError
          cache = {}
        end 
      end
    end
    cache ||= {}
    profile_names =  []
    profile_path ||= @profile_path 
    aws_config = IniFile.load( profile_path )
    required_fields = %w[ aws_access_key_id aws_secret_access_key ]
    aws_config.each_section { |section| 
      if (aws_config[section].keys & required_fields ).length == required_fields.length
          profile_names << section
       end
    }
    old_names = names - profile_names
    old_names.each { |n| @profiles.delete n }
    new_names = profile_names - names
    new_names.each do |name|
      @profiles[name] = Profile.new( name, aws_config[name] )
      @profiles[name].discover_profile_data cache[name]
    end
    cache
  end
  def cache
    cache = {}
    @profiles.each {|name,profile|
      puts "Caching #{name}"
      cache[name] = profile.make_cache
    }
    cache = cache.to_json
    puts cache
    File.open( "/tmp/ec2_roles.json", "w" ) do |f|
      f.write(  cache.to_json ) 
    end
  end
  def current_role
    return nil if not @current
    return @profiles[@current].current_role
  end
end


profiles = Profiles.new( profile_path )

class ProfileAuthException < RuntimeError; end

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/cookies'
require 'tilt/erubis' 
require 'json'
require 'shellwords'
require 'open3'

set :bind, '0.0.0.0'
set :port, 4567
set(:cookie_options) do
  { :expires => Time.now + 86400*365 }
end

get %r|/latest/meta-data/iam/security-credentials/?$| do
 if profiles.current_role
   profiles.current_role
  else
    nil
  end
end

#require 'digest/sha1' # crc should be faster!
require 'zlib' 
require 'date'

get %r|^/config/current$| do 
    if profiles.current_role
      redirect "/config/#{profiles.current_role}", 303 
    else
      status 404
      "No role is set"
    end
end

get %r|^/config/(.+)/?$| do
  content_type 'text/plain'
  erb :config, { locals: { role: params['captures'].first, profile_auth: profiles.current.credentials, region: params[:region] || nil  } }
end

get %r|/latest/meta-data/iam/security-credentials/(.+)| do
  if profiles.current_role
    if params['captures'].first == profiles.current_role
      credentials = profiles.current.credentials
      data = JSON.pretty_generate credentials
      content_type 'text/json'
      etag Zlib::crc32(data).to_s
      last_modified DateTime.parse( credentials[:LastUpdated] )
      data
    else
      status 404
    end
  end
end


get '/using-config' do 
  erb :using_config
end

post '/authenticate' do 
  if profiles.current_profile
    result = profiles.profile.assume_role params
    if result['status'].exitstatus == 0 
      status 200
      content_type 'text/json'
      redirect back, '[]' #, JSON.pretty_generate(result)
    else
      status 500
      content_type 'text/html'
      "<p><b>Failed to assume role:</b> <code>#{ result[:stderr] }</code></p> <p>Please use the back button on your browser to try again.</p>"
    end
  else
    status 403
    content_type "text/html"
    "A profile has not yet been selected; please select a profile"
  end
end

get '/' do  
  erb :index, { locals: { profiles: profiles, profile: profiles.profile } }
end

get '/identity' do 
  content_type "application/json"
  `aws sts get-caller-identity`
end

get '/profile' do
  if profiles.current_profile
    profiles.current_profile
  else
    status 404
    "No current profile"
  end
end 

instance_id = nil
post '/latest/meta-data/instance-id' do
  request.body.rewind
  instance_id = request.body.read 
  if len(instance_id) == ''
    instance_id = nil
  end
  status 204
end

get '/latest/meta-data/instance-id' do
  if instance_id 
    content_type 'text/plain'
    instance_id.to_s
  else
    status 404
  end
end

post '/profiles/refresh' do
  profiles.load_profiles
  redirect back, ""
end

post '/profile' do
  begin 
  if params[:profile] == "" or params[:profile] == nil
    profiles.set_current_profile nil
    redirect '/', 303 
  elsif profiles.names.include? params[:profile]
    profiles.set_current_profile params[:profile]
    redirect '/', 303 
  else
    status 404
    "Couldn't change profile: no such profile '#{params[:profile]}' in #{profiles.names }"
  end
  rescue ProfileAuthException => e
    status 401
    content_type "text/plain"
    e.message
  end
end

