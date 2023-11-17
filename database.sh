#!/bin/sh

. ./.env

die() {
	cat >&2
	exit 1
}

create() {
	sqlite3 "$DATABASE" ''
	echo "Database created: $DATABASE"
}

migrate() {
	if [ -z "$1" ]; then
		die <<-USAGE
			Usage: $0 migrate <file>
		USAGE
	fi
	sqlite3 "$DATABASE" ".read '$1'"
	echo "Database migrated: $1"
}

delete() {
	rm "$DATABASE"
	echo "Database removed: $DATABASE"
}

case "$1" in
create)
	shift
	create
	;;
migrate)
	shift
	migrate "$@"
	;;
delete)
	shift
	delete
	;;
'')
	die <<-USAGE
		Usage: $0 <command> [<args>]

		Commands:
		    create      Create database
		    migrate     Migrate database
			delete      Delete database
	USAGE
	;;
*)
	die <<-MSG
		ERROR: unknown command: $1
		Run '$0' to see help.
	MSG
	;;
esac
