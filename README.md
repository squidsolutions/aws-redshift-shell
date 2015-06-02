# Redshift administration scripts

Here are some scripts we wrote at [squidsolutions.com](http://www.squidsolutions.com); they help us administrate the [AWS Redshift](http://aws.amazon.com/redshift/) clusters we are in charge of.

# Redshift start/stop script

The `bin/redshift.sh` script ensures that a cluster's configuration and data are saved upon restart. In fact, stopping a redshift cluster is more like a cluster deletion. If you don't do it properly, you will loose:

* The cluster's data
* The cluster's network configuration (In a VPC ? In which subnet group ? With which security group ? etc.)
* The cluster's parameter group name

`bin/redshift.sh` automatically creates a final data snapshot and saves these informations in a JSON file. During the cluster start, the script will restore these informations. Run from a crontab, it can help you save a lot of money.

## Pre-requisites

You must have [awscli](http://aws.amazon.com/cli/) and [jq](http://stedolan.github.io/jq/) installed:

```
pip install awscli
apt-get install jq
```
## Configuration

The `etc/redshift.conf` file handles a few configuration variables. See the inline comments for more details.

## Usage

```
./bin/redshift.sh
Usage: ./bin/redshift.sh  -a {start|stop|save} -r aws_region -c cluster_name [-p awscli-profile]
```

* *-a*: The *action* to take,
* *-r*: The AWS *region* in which the cluster is defined,
* *-c*: The *name* of the cluster,
* *-p*: The name of the profile used by awscli.

The *stop* and *save* actions will create a .json file in the `etc/` directory for each cluster you need to start/stop.

## Crontab example

Say you want your dev cluster up and running at working hour (not during the week-end):

```
0 20 * * 1-5 /opt/squid/aws-redshift-shell/bin/redshift.sh -a stop -r us-east-1 -c dev-cluster -p myCompany
0 8 * * 1-5 /opt/squid/aws-redshift-shell/bin/redshift.sh -a start -r us-east-1 -c dev-cluster -p myCompany
```

Note that, depending on the cluster's size, it may take time to be fully started.


# License

The shell scripts inside the `bin/` directory are licensed under the GNU General Public License (GPL) v.3.

# Authors

* Grégoire Doumergue https://github.com/gdoumergue
