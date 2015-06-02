# Redshift administration scripts

Here are some scripts we wrote at [squidsolutions.com](http://www.squidsolutions.com); they help us administrate the [AWS Redshift](http://aws.amazon.com/redshift/) clusters we are in charge of.

# Redshift start/stop script

The `bin/redshift.sh` script ensures that a cluster's configuration and data are saved upon restart. In fact, stopping a redshift cluster is more like a cluster deletion. If you don't do it properly, you will loose:

* The cluster's data
* The cluster's network configuration (In a VPC ? In which subnet group ? With which security group ? etc.)
* The cluster's parameter group name

`bin/redshift.sh` automatically saves these informations in a JSON file and uses them when you start the cluster. Run from a crontab, it can help you save a lot of money.

## Pre-requisites

You must have [awscli](http://aws.amazon.com/cli/) and [jq](http://stedolan.github.io/jq/) installed:

```
pip install awscli
apt-get install jq
```

## Usage

```
./bin/redshift.sh
Usage: ./bin/redshift.sh  -a {start|stop|save} -r aws_region -c cluster_name [-p awscli-profile]
```

* *-a*: The *action* to take,
* *-r*: The AWS *region* in which the cluster is defined,
* *-c*: The *name* of the cluster,
* *-p*: The name of the profile used by awscli.

# License

The shell scripts inside the `bin/` directory are licensed under the GNU General Public License (GPL) v.3.

# Authors

* Grégoire Doumergue https://github.com/gdoumergue
