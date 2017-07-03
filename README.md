An EC2 Metadata role credentials service
---------------------------------------------

Simplify the process of assuming AWS roles and authenticating with MFA tokens with this web wrapper to AWS CLI commands.  

This service provides:

* an interface to assume roles to configure those credentials through a web interface;
* a configuration file endpoint that can be used by `curl` to generate config files using the assumed token from the web interface and a specified role ( great for automated testing);
* optionally, an endpoint on 169.254.169.254:80 that can answer AWS client requests for credentials (boto, aws-sdk-ruby, and others will try to pull from here automatically )

Configuring the ec2 metadata endpoint requires superuser privileges to create the IP address 169.254.169.254 on the loopback device and configuring a redirect from port 80 to the docker container.  

# Quick Start

Ensure that `~/.aws/credentials` holds your IAM profiles with keys and secrets.   **See note about the default profile**
```
./setup.sh
make daemon
```

Now, go to http://169.254.169.254 to select a profile and start assuming roles.

# Running the app

## Dockerhub image

This repo is now in dockerhub!  https://hub.docker.com/r/farrellit/ec2metadata/ can save you the effort of building yourself.   The Makefile is updated accordingly.

## AWS Setup

The program expects to find credentials in either `~/.aws/credentials` or `/code/.aws/credentials` (useful in docker). You choose the profile in the application.

## Invocation

### Metadata Service on 169.254.169.254

Before beginning, run `setup.sh`. This will create the `iptables`/`pfctl` rules to allow port 80 forwarding.  This requires sudo access as port 80 is a privileged port.


#### Metadata service caveats

##### `default` profile supercedes metadata service

The metadata service is the _lowest_ priority in the order of precedence. This means that if you have a `default` profile in the `.aws` configurations exposed to an applicaiton, this will _override_ the metadata service.  

You can still use the application anywhere that doesn't expose `~/.aws` - for example docker containers or virtual machines - but it won't show the assumed role in `aws sts get-caller-identity` from the ec2 metadata service ( which uses `~/.aws` itself to generate session tokens) or from your local machine.  I recommend naming each profile something _other_ than default if you use multiple accounts, and just specifying the correct profile for `aws` commands with `--profile`. 

If the clock is off, the metadtaservice won't work, and the webiste doesn't currently make this as clear as it should.  This is unlikely on linux as the system time is used, but in Docker for Mac, and maybe Docker for Windows, the underlying virtual machine clock has a tendency to drift.  This command uses ntp to fix the clock: 

```
docker run -it --rm --privileged --pid=host debian nsenter -t 1 -m -i sh -c "ntpd -q -n -p pool.ntp.org"
```



### Config writer service

You don't need this to be on 169.254.169.254:80, and so super user isn't required to configure the IP or create the port 80 redirect.  You can skip `setup.sh`.  Use the built in config writer to expose credentials to docker or other applications via configuration files.   You can access the service on http://localhost:8009 .

### Launching the service

Regardlesss of whether you chose to use `setup.sh`, launch the ec2 metadata container with

```
make
```

If this fails because `make` is not available, simply `cat Makefile` and you'll be on your way to running the very simple invocation of `docker run ... ` to produce a running server.

### Launchiung as a daemon

```
make daemon
```

## Usage

Navigate to <http://169.254.169.254>.

### Web flow

1. Select a profile and submit the form.
  a) enter your MFA token now, if you'd like to generate a session token, obviating the need to enter a session token every time a role is assumed.  
  b) optionally select or deselect the 'List Roles' checkbox
2. Patiently await the loading of the roles under that account (your user requires read permission for this of course).  Or, if impatient, deselect the List Roles checkbox on the previous page.
3. To expose a role globally to your computer ( and all virtual machines and docker containers that route through it), select the desired role from the list, or enter in its ARN and submit.  Thereafter, 169.254.169.254 supplies credentials to the local machine, for any AWS SDK that uses the standard credential search processes ( which is all of them, I think).  
  a) enter your MFA token if you wish to provide it with the role assumption call.  This isn't strictly required.
  b) select the 'Refresh' checkbox if you'd like the service to renew the credentials when they expire.
4. To generate a config file, curl 'http://localhost:8009/config/role-arn' ( or http://169.254.169.254/config/role-arn if its configured) to generate a configuration file which will direct the SDKs to assume `role-arn` automatically using the temporary session token from step 1.   Note that step 3 is _not_ required to do this.  

### Using the config generator to support multiple roles simultaneously

Once you'e selected a profile, and (optionally) entered MFA, this technique can be used to assume roles for each application.  Very useful for testing your AWS lambdas or programs with the correct credentials.

In this case I assume the `arn:aws:iam::122377349983:role/nothing` role.  This doesn't allow any access, but is assumable (with MFA) by any  account so it's great for testing.

```
  curl -s http://localhost:8009/config/arn:aws:iam::122377349983:role/nothing > ~/.aws/farrellit.nothing
  docker run -v `ls -d ~`/.aws/farrellit.nothing:/root/.aws/config:ro farrellit/awscli:latest sts get-caller-identity
```

I typically add commands such as these to a Makefile that specifies the role appropriate for the application.  

### Arbitrary metadata

If you are on a non-EC2 instance developing an application that interacts with the EC2 metadata service's many endpoints ( for example, subnet discovery ,VPC discovery ,etc ), you may find it convenient to be able to set arbitrary parts of the metadata to user-supplied values.  There is a route to support this; anything posted to `/latest/meta-data/<key>` will be available on `/latest/meta-data/<key>` with subsequent GETs.  So you can set, for example, an instance ID or a VPC ID or a Subnet ID, whatever you like.  There is no validation that the URL be extant in the _real_ ec2 metadata service; it just saves and returns.  

Observe:

```
$  curl localhost:8009/latest/meta-data/instance-id -X POST --data  "i-1234567890abcdef"

$  curl localhost:8009/latest/meta-data/instance-id
i-1234567890abcdef

$ curl localhost:8009/latest/meta-data
{
  "instance-id": "i-1234567890abcdef"
}

$  curl localhost:8009/latest/meta-data/instance-id -X POST --data  "" # empty string

$ curl localhost:8009/latest/meta-data
{
}
```
Above, I've added newlines to the output for readability - but, consistent with the real EC2 metadata service, I do not add newlines or other trailing whitespace to the responses from these endpoints.  All POSTed data is preserved as a string.  
