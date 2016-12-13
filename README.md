# ec2 metadata role credentials stub service

Provides an endpoint on 169.254.169.254:80 that can answer AWS client requests for credentials (boto, aws-sdk-ruby, and others will try to pull from here automatically ), and an interface to assume roles to configure those credentials through a web interface.

## Network Setup

You need a local 169.254.169.254 address which can be routed by local sources.

`setup.sh` has been my dumping ground for commands. I've found the `pf` stuff to be a good solution o osx. I think there's an `iptables` invocation for linux. It's absolutely critical that you make sure this is only available locally.

### AWS Setup

The program expects to find credentials in either `~/.aws/credentials` or `/code/.aws/credentials` (useful in docker). You choose the profile in the application.

## Invocation

Before beginning, run `setup.sh` as root. This will create the iptables rules to allow port 80 forwarding.

You are now ready to launch the ec2 metadata role. Docker makes this easy, simply run

```
make
```

If this fails because `make` is not available, simply `cat Makefile` and you'll be on your way to running the very simple invocation of `docker-compose` to produce a running server.

## Usage

Navigate to <http://169.254.169.254>.

1. Select a profile.
2. Patiently await the loading of the roles under that account (your user requires read permission for this of course)
3. Select the desired role from the list.
4. Type in MFA token, configure time if desired
5. Submit
6. 169.254.169.254 supplies credentials to the local machine, for any AWS SDK that uses the standard credential search processes
7. Browser back button is shamefully required to complete cycle and return to the main role selection page

It's pretty self explanatory and quite simplistic, barely adequate for the job.
