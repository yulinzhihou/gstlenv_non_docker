# Initial SQL

Small, versioned initialization SQL is shipped with the online installer here.
These files were copied from the existing `offline/sql/` distribution. Binary
offline packages remain excluded from Git.

MySQL 8.4 uses `mysql80/`. In three-database mode the installer rewrites only
the `CREATE DATABASE` and `USE` directives in `tlbbdb.sql` to `tlbbdb_main`.
Existing databases containing tables are not automatically reimported.

An explicit `TLBB_SQL_DIR` overrides the bundled directory. Keep all files for
the selected layout together: `tlbbdb.sql`, `web.sql`, and, for three databases,
`tlbbdb_10.sql`.
