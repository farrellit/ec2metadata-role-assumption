
role_regex=':role/app/|sps-iam'

`which aws`
unless $?.exitstatus == 0
  abort "Can't run without the aws command line utility to assume session token"
end

required_env_keys = %w[ AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION ]
missing_env_keys = required_env_keys - ENV.keys 
unless missing_env_keys.empty? 
  fail "Missing environment variables: #{missing_env_keys.inspect}"
end

roles = []
`aws iam list-roles --query *[*].[Arn] --output text | egrep '#{role_regex}'`.lines.each do |line|
  roles << line.strip
end
roles.sort! do |a,b|
  if a =~ %r|:role/app/| 
    1
  elsif b =~ %r|:role/app/|
    -1
  else
    a <=> b
  end
end

mfa_devices =[]
`aws iam list-mfa-devices --query MFADevices[*].SerialNumber --output text`.each_line do |line|
  $stderr.puts "MFA Device: #{line}"
  mfa_devices << line.strip
end

current_role = nil

require 'sinatra'
require 'tilt/erubis' 
require 'json'
require 'shellwords'
require 'open3'

set :bind, '0.0.0.0'
set :port, 4567

credentials = nil

get '/latest/meta-data/iam/security-credentials/' do
 if current_role
    current_role
  end 
end

get %r|/latest/meta-data/iam/security-credentials/(.+)| do
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
  command = "aws sts assume-role --role-arn #{Shellwords.escape params[:role]} --role-session-name assumed-role --serial-number #{Shellwords.escape params[:serial]} --token-code #{Shellwords.escape params[:mfa]} --duration-seconds #{Shellwords.escape params[:duration]}"
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
    result['credentials'] = credentials
    current_role = params[:role]
    status 200
  else
    status 500
  end
  content_type 'text/json'
  JSON.pretty_generate(result)
end

get '/' do
  erb :index, { locals: { mfa_devices: mfa_devices,  :roles => roles } }
end

get '/debug' do
  { :mfa_devices => mfa_devices,  :roles => roles, credentials: credentials, current_role: current_role }.to_json
end
