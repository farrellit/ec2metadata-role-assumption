# ec2 metadata role credentials stub service

Provides an endpoint on 169.254.169.254:80 that can answer AWS client requests for credentials (boto, aws-sdk-ruby, and others will try to pull from here automatically ),  and an interface to assume roles to configure those credentials through a web interface.  

## Setup

`setup.sh` sets up your environment with an alias on lo for Mac OSX users.  As long as you can 
bind to `169.254.169.254`, you should be good; it can be on an interface or a virtual interface or 
a loopback, but don't put it on the network, as this service exposes your credentials.

### Recommended AWS setup

Export AWS_SECRET_ACCESS_KEY & AWS_ACCESS_KEY_ID or AWS_DEFAULT_PROFILE in the shell that's executing the ruby server.  

These variable override the metadata lookup so you can override the credentials provided by this service for a particular shell, but be aware that if not otherwise configured, all shells and programs will otherwise have access to the roles assumed through the metadata service.  

## Invocation

Invocation requires sudo so it can bind to port 80, but there are other options 
if you don't want to run as sudo ( you'll have to allow it to bind to 80 in some 
other way or forward port 80 requests; I don't know of a way to configure the 
metadata server for boto to be on some other port or address )

`./setup.sh`
`sudo -E bundle exec ruby ec2metadata.rb`

## Usage

Navigate to http://169.254.169.254 and, if invoked as a user that has access, you should see a select dropdown for all the roles that match the regex 
can assume.  

Select the appropriate role and enter your MFA token, and if desired adjust the expriry time ( in seconds ).  

Once you submit, your new session tokens for that role should be available.  You'll also see them in an iframe below the 
assumption form. 
