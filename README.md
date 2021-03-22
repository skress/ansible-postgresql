## Ansible PostgreSQL Role with Support for Repmgr and Barman

Ansible role which installs and configures PostgreSQL, extensions, databases and users.

This role is a fork of [ANXS.postgresl](https://github.com/ANXS/postgresql) with the following changes

- integrated all outstanding PRs which seemed reasonable (as of June 2020)
- especially merged Repmgr extension (created by https://github.com/Demonware/postgresql)
- added support for backups via Barman (https://www.pgbarman.org)

I am only testing this on Ubuntu 20.04 and the latest stable PostgreSQL version. Barman will only be installed on Debian-like systems, so there is even no code for RedHat et. al.

This has been tested on Ansible 2.10.5. 

#### Dependencies

- ANXS.monit ([Galaxy](https://galaxy.ansible.com/list#/roles/502)/[GH](https://github.com/ANXS/monit)) if you want monit protection (in that case, you should set `monit_protection: true`)

#### Variables

```yaml
# Basic settings
postgresql_version: 13
postgresql_encoding: "UTF-8"
postgresql_locale: "en_US.UTF-8"
postgresql_ctype: "en_US.UTF-8"

postgresql_admin_user: "postgres"
postgresql_default_auth_method: "peer"

postgresql_service_enabled: false # should the service be enabled, default is true

postgresql_cluster_name: "main"
postgresql_cluster_reset: false

# List of databases to be created (optional)
# Note: for more flexibility with extensions use the postgresql_database_extensions setting.
postgresql_databases:
  - name: foobar
    owner: baz          # optional; specify the owner of the database
    hstore: yes         # flag to install the hstore extension on this database (yes/no)
    uuid_ossp: yes      # flag to install the uuid-ossp extension on this database (yes/no)
    citext: yes         # flag to install the citext extension on this database (yes/no)
    encoding: "UTF-8"   # override global {{ postgresql_encoding }} variable per database
    lc_collate: "en_GB.UTF-8"   # override global {{ postgresql_locale }} variable per database
    lc_ctype: "en_GB.UTF-8"     # override global {{ postgresql_ctype }} variable per database

# List of database extensions to be created (optional)
postgresql_database_extensions:
  - db: foobar
    extensions:
      - hstore
      - citext

# List of users to be created (optional)
postgresql_users:
  - name: baz
    pass: pass
    encrypted: yes  # if password should be encrypted, postgresql >= 10 does only accepts encrypted passwords

# List of schemas to be created (optional)
postgresql_database_schemas:
  - database: foobar           # database name
    schema: acme               # schema name
    state: present

  - database: foobar           # database name
    schema: acme_baz           # schema name
    owner: baz                 # owner name
    state: present

# List of user privileges to be applied (optional)
postgresql_user_privileges:
  - name: baz                   # user name
    db: foobar                  # database
    priv: "ALL"                 # privilege string format: example: INSERT,UPDATE/table:SELECT/anothertable:ALL
    role_attr_flags: "CREATEDB" # role attribute flags
```

There's a lot more knobs and bolts to set, which you can find in the [defaults/main.yml](./defaults/main.yml)

#### Replication with repmgr, backups with Barman

There is initial support for setting up and running with replication managed by [repmgr](https://repmgr.org/) and backups with [Barman](https://www.pgbarman.org). In it's current state it has only been tested with repmgr-5.2 and barman-2.12 on Ubuntu 20.04 and requires Systemd.

When repmgr is enabled (i.e. setting `postgresql_ext_install_repmgr: yes`) all hosts in your play are included in the replication cluster. The first host in your play is chosen as the initial primary. You can designate hosts as witness server by setting `repmgr_witness=true` for any host (except your first host).

When barman is enabled (i.e. setting `postgresql_ext_install_barman: yes`) then you need to designate exactly one host as your barman server by setting `barman_server=true` for that host.

If both repmgr and barman are enabled then the primary server will be backed up. If repmgr is disabled you can designate any number of hosts to be backed up via setting `barman_backup_node=true` for these hosts.

Additionally if both extensions are enabled, the barman server needs to be configured as witness server, so `barman_server=true` and `repmgr_witness=true` should be set.

Usage of replication slots is the default in this configuration for barman and repmgr. (If you do not want to use replication slots, you need to set `repmgr_use_replication_slots` to false and increase `postgresql_wal_keep_segments`.) This has not been tested.

To enable repmgr, the following variables need to be set:

```yaml
# Manage replication with repmgr (mandatory)
postgresql_ext_install_repmgr: yes
repmgr_major_version: 5
repmgr_minor_version: 2
repmgr_password: "password"
repmgr_network_cidr: "127.0.0.1/32" # change to allow access between nodes
```

When repmgr is enabled, a couple of settings for the PostgreSQL installation will get different defaults. You need to take care not to specify incompatible settings for your specific configuration.

```yaml
postgresql_wal_level: "replica"
postgresql_max_replication_slots: 10
postgresql_hot_standby: on
postgresql_archive_mode: on
postgresql_archive_command: '/bin/true'
postgresql_shared_preload_libraries:
  - repmgr
```

Depending on the size of your cluster you might need more replication slots. In that case you need to override the default.

Additionally the following users, databases, and user privileges will be created automatically:

```yaml
users:
  - name: "{{ repmgr_user }}"
    pass: "{{ repmgr_password }}"

databases:
  - name: "{{ repmgr_database }}"
    owner: "{{ repmgr_user }}"
    encoding: "UTF-8"

user_privileges:
  - name: "{{ repmgr_user }}"
    db: "{{ repmgr_database }}"
    priv: "ALL"
    role_attr_flags: "SUPERUSER,REPLICATION"
```

When barman is enabled, the following variables should be adapted:

```yaml
barman_pg_password: "password"
barman_pg_streaming_password: "password"
barman_server_ip_or_cidr: "127.0.0.1/32"
```

Barman will be configured to use streaming replication. This role does not support other barman configurations (e.g. rsync via ssh).

This playbook makes a lot of assumptions when using barman in combination with repmgr:
- For the initial installation a backup configuration is created for the repmgr primary.
- Additionally for all other standbys a backup configuration is created which ends in '.conf.hold' such that this configuration is not automatically picked up by barman's cron job.

When re-running this playbook:
- ... it checks if there is a '<node_name>.conf.hold' file for the current primary, if yes the playbook fails
- ... it checks if there is a '<node_name>.conf' file for any standby, if yes the playbook fails
- ... it makes sure that there is a backup config ('<node_name>.conf') for the current primary
- ... it makes sure that there is a backup config ('<node_name>.conf.hold') for the all standby nodes

When a failover or switchover occurs, you should manually disable the backup from the previous primary by running `/var/lib/barman/bin/disable-backup.sh <server_name>` as root and then enabling the backup for the newly elected primary by running `/var/lib/barman/bin/enable-backup.sh <server_name>`.

Re-enabling a backup (e.g. you previously switched over to another host and now back to your old hast again) might result in errors. So carefully look at the command output when enabling the backup.

You might need to run a couple of commands as 'barman':
```bash
barman receive-wal --create-slot <new_primary_hostname>
barman cron
# now check output of log
less /var/log/barman/barman.log
# probably we need to reset the receive-wal process
barman receive-wal --reset <new_primary_hostname>
barman backup <new_primary_hostname>
```

##### Node fencing with repmgr

There is a document in the repmgr Github repository about [node fencing](https://github.com/EnterpriseDB/repmgr/blob/master/doc/repmgrd-node-fencing.md). This document is linked from [repmgrd-basic-configuration](https://repmgr.org/docs/current/repmgrd-basic-configuration.html) in the official guide.

The problem with the node fencing example is that it requires all hosts that "create the fence" to be available when the new primary is promoted. If you have a couple of PgBouncer nodes, and all of these nodes are available during promotion, you can successfully fence off the failed primary.

But consider a setup where you have 3 nodes together with a PgBouncer in DC1 and 2 nodes with a PgBouncer in DC2. You did a switchover to DC2. Now DC2 goes down. The 3 nodes in DC1 have a quorom and elect a new primary. The PgBouncer in DC1 is properly configured during promotion of the new primary. The PgBouncer in DC2 is not reachable, so it cannot be reconfigured.

At some point in time DC2 comes back online. The previous primary still considers itself to be a primary and the PgBouncer in DC2 is also still configured to route the requests to the old primary.

This is exactly the situation that should not happen ... it's also documented as an open issue in this [repmgr Github issue](https://github.com/EnterpriseDB/repmgr/issues/497).

If you want to simply stop routing requests to any PostgreSQL server in case that there is more than 1 primary online, please take a look at https://github.com/gplv2/haproxy-postgresql.

My take on this is: when there was a successful failover to a new primary, I simply do not want any old primary to become available. On the other hand, I had hoped that repmgr would solve this problem such that I do not have to install another distributed system like etcd, consul, ZooKeeper, ...

So my layman's solution can be used when setting `repmgr_fencing_enabled` to `true`. I did not want to add any new complicated services to the mix - ideally just some shell scripts which are started via cron. Currently it looks like this:

There are a couple of shell scripts which are started via cron every minute. The result is that a file is written (ca every 20s) to `/var/lib/postgresql/fencing/cluster_state/13/main/current_primary` and if you enable HAProxy support additionally to `/var/lib/haproxy/current_primary` which contains the current primary PostgreSQL node.

There are two scripts involved: the first runs on each host and uses repmgr's 'cluster show' to see if there is only one primary running. In the example above all nodes in DC1 which had a quorum to elect a new primary will write the hostname of that primary into a file and then this file is distributed via rsync to all other (reachable) nodes. The script on the nodes in DC2 will find some problems via 'cluster show' and just write empty files, i.e. they do not declare any current primary (they also distribute that empty file to all reachable nodes).

The second script runs on each node and simply counts the number of votes from each server as long as that vote file is not older than 1 minute. If a node has the needed number of votes (`repmgr_fencing_quorum` which defaults to 1 more than half the number of nodes), this node is declared as the current running primary and its name is written to the `current_primary` file as described earlier. If no node could be declared as the running primary, then `current_primary` is changed to be an empty file. 

If HAProxy support is enabled, an xinetd service is added which listens on port 23267 for each PostgreSQL node and returns "200 OK" if that node is currently the detected primary, otherwise a "503 Service Unavailable" is returend. The check script which is launched from xinetd checks if the `current_primary` is not older than 1 minute, if it was written after the PostgreSQL service entered the active state, and if its contents are equal to the hostname where the xinetd service is running. Note that this xinetd service is run as user haproxy just because that user is already available on the system and has restricted privileges (e.g. may not login).

Alle these bits and pieces are not providing the current state immediately, there is some lag. But when the current primary starts to fail, it should take at least a minute, probably more before an automatic failover is started. At that time HAProxy already marked all servers as down. When a new primary is elected, it will not be immediately visible in HAProxy - it just takes a maximum of 30 seconds until all scripts have updated the final state. So for most scenarios it should be good enough.

#### Testing

Testing will probably not work anymore ...

This project comes with a Vagrantfile, this is a fast and easy way to test changes to the role, fire it up with `vagrant up`

See [vagrant docs](https://docs.vagrantup.com/v2/) for getting setup with vagrant

Once your VM is up, you can reprovision it using either `vagrant provision`, or `ansible-playbook tests/playbook.yml -i vagrant-inventory`

If you want to toy with the test play, see [tests/playbook.yml](./tests/playbook.yml), and change the variables in [tests/vars.yml](./tests/vars.yml)

If you are contributing, please first test your changes within the vagrant environment, (using the targeted distribution), and if possible, ensure your change is covered in the tests found in [.travis.yml](./.travis.yml)


#### License

Licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

#### Thanks

Creator:
- [Pjan Vandaele](https://github.com/pjan)

Maintainers:
- [Jonathan Lozada D.](https://github.com/jlozadad)
- [Jonathan Freedman](https://github.com/otakup0pe)
- [Sergei Antipov](https://github.com/UnderGreen)
- [Greg Clough](https://github.com/gclough)

Top Contributors:
- [David Farrington](https://github.com/farridav)
- [Jesse Lang](https://github.com/jesselang)
- [Michael Conrad](https://github.com/MichaelConrad)
- [Sébastien Alix](https://github.com/sebalix)
- [Copperfield](https://github.com/Copperfield)

- [Ralph von der Heyden](https://github.com/ralph)
