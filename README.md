## Ansible PostgreSQL Role with Support for Repmgr and Barman

Ansible role which installs and configures PostgreSQL, extensions, databases and users.

This role is a fork of [ANXS.postgresl](https://github.com/ANXS/postgresql) with the following changes

- integrated all outstanding PRs which seemed reasonable (as of June 2020)
- especially merged Repmgr extension (created by https://github.com/Demonware/postgresql)
- added support for backups via Barman (https://www.pgbarman.org)

I am only testing this on Ubuntu 20.04 and the latest stable PostgreSQL version. Barman will only be installed on Debian-like system, so there is even no code for RedHat et. al.

This has been tested on Ansible 2.9.10. 

#### Dependencies

- ANXS.monit ([Galaxy](https://galaxy.ansible.com/list#/roles/502)/[GH](https://github.com/ANXS/monit)) if you want monit protection (in that case, you should set `monit_protection: true`)

#### Variables

```yaml
# Basic settings
postgresql_version: 12
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

There is initial support for setting up and running with replication managed by [repmgr](https://repmgr.org/) and backups with [Barman](https://www.pgbarman.org). In it's current state it has only been tested with repmgr-5.1 and barman-2.11 on Ubuntu 20.04 and requires Systemd.

When repmgr is enabled (i.e. setting `postgresql_ext_install_repmgr: yes`) all hosts in your play are included in the replication cluster. The first host in your play is chosen as the initial primary. You can designate hosts as witness server by setting `repmgr_witness=true` for any host (except your first host).

When barman is enabled (i.e. setting `postgresql_ext_install_barman: yes`) then you need to designate exactly one host as your barman server by setting `barman_server=true` for that host.

If both repmgr and barman are enabled then the primary server will be backed up. If repmgr is disabled you can designate any number of hosts to be backed up via setting `barman_backup_node=true` for these hosts.

Additionally if both extensions are enabled, the barman server needs to be configured as witness server, so `barman_server=true` and `repmgr_witness=true` should be set.

Usage of replication slots is the default in this configuration for barman and repmgr. (If you do not want to use replication slots, you need to set `repmgr_use_replication_slots` to false and increase `postgresql_wal_keep_segments`.)

To enable repmgr, the following variables need to be set:

```yaml
# Manage replication with repmgr (mandatory)
postgresql_ext_install_repmgr: yes
repmgr_version: "5.1"
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

When using barman in combination with repmgr, you can set the variable `barman_repmgr_backup_name` for your first host (i.e. the initial primary in your cluster. In that case the specified name will be used as the name for the backup configuration. Otherwise the hostname for your primary will be the name for your backup. (But that would get confusing when you should swith to a different primary later on.)

Please note that in the case of switching over to a different master you would need to adapt your backup configuration manually.

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
