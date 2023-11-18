#!/bin/sh

set -eu

. ./.env

###############################################################################
# Helpers
###############################################################################

log_info() {
	echo "$(date -Is) | INFO | $1" >&2
}

###############################################################################
# Response
###############################################################################

response_rqline='HTTP/1.1 500 Internal Server Error'
response_fields=

# $1 - HTTP response status
set_rqline() {
	response_rqline="HTTP/1.1 $1"
}

# $1 - Field name
# $2 - Field value
add_field() {
	response_fields="$response_fields$1: $2!!!"
}

respond() {
	printf '%s\r\n' "$response_rqline"
	printf '%s' "$response_fields" | sed 's/!!!/\r\n/g'
	printf '\r\n'
	sed 's/$/\r/'
}

respond_html() {
	set_rqline '200 Ok'
	add_field 'Content-Type' 'text/html'
	respond
}

respond_raw() {
	printf '%s\r\n' "$response_rqline"
	printf '%s' "$response_fields" | sed 's/!!!/\r\n/g'
	printf '\r\n'
	cat
}

respond_head() {
	printf '%s\r\n' "$response_rqline"
	printf '%s' "$response_fields" | sed 's/!!!/\r\n/g'
	printf '\r\n'
}

redirect() {
	set_rqline '303 See Other'
	add_field 'Location' "$1"
	respond_head
}

serve_static() {
	! [ -f ./static/"$path" ] && return 1

	if [ "$path" = '/favicon.ico' ]; then
		set_rqline '200 Ok'
		add_field 'Content-Type' 'image/x-icon'
		respond_raw <./static/"$path"
		return
	fi

	set_rqline '200 Ok'
	add_field 'Content-Type' "$(mimetype -b ./static/"$path")"
	respond_raw <./static/"$path"
}

serve_404() {
	set_rqline '404 Not Found'
	add_field 'Content-Type' 'text/html'
	j2 ./templates/404.html | respond
}

###############################################################################
# Request
###############################################################################

raw=$(
	cat <<-RAW
		$(timeout .1 cat - 2>&1)
	RAW
)

read -r method path version <<-RAW
	$raw
RAW

case "$method" in
GET | HEAD | POST | PUT | DELETE | CONNECT | OPTIONS | TRACE | PATCH) ;;
*)
	set_rqline '400 Bad Request'
	respond_head
	;;
esac

case "$path" in
*\?*)
	query=${path##*\?}
	path=${path%%\?*}
	;;
*)
	query=
	;;
esac

version=${version%%[[:space:]]}

case "$version" in
HTTP/1.1) ;;
*)
	set_rqline '505 HTTP Version Not Supported'
	respond_head
	;;
esac

# $1 - GET query parameter
query() {
	sed -n 's/.*'"$1"'=\([^&]*\).*/\1/p' <<-RAW
		$query
	RAW
}

# $1 - POST payload parameter
data() {
	raw="$raw" key="$1" perl -e '
		my @lines = split /\r\n/, $ENV{raw};
		$ENV{raw} = @lines[$#lines];
		my @keypairs = split /&/, $ENV{raw};
		for (@keypairs) {
			if ($_ !~ /^$ENV{key}=/) {
				next;
			}
			my @pair = split /=/, $_;
			$pair[1] =~ s/.*\b$ENV{key}=([^&]*).*/$1/;
			$pair[1] =~ s/%(..)/chr(hex($1))/eg;
			print $pair[1];
			last;
		}
	'
}

# $1 - Cookie name
cookie() {
	raw="$raw" cookie="$1" perl -e '
		my @lines = split /\r\n/, $ENV{raw};
		foreach (@lines) {
			if ($_ !~ /^Cookie: /) {
				next;
			}
			if ($_ !~ s/.*$ENV{cookie}=([^&]*).*/$1/) {
				next;
			}
			$_ =~ s/%(..)/chr(hex($1))/eg;
			print $_;
			exit;
		}
	'
}

###############################################################################
# Routing
###############################################################################

# $1 - Method
# $2 - Path
# $3 - Handler
route() {
	[ "$method" != "$1" ] && return 1

	case "$2" in
	*/:*)
		"$3" "$(awk -vtgt="$2" -vrecv="$path" \
			'BEGIN {
				nb_tgts = split(tgt, tgts, "/")
				nb_recvs = split(recv, recvs, "/")
				if (nb_tgts != nb_recvs) {
					exit 1
				}
				for (i = 1; i <= nb_tgts; i += 1) {
					if (substr(tgts[i], 1, 1) ~ /:/) {
						param = recvs[i]
						continue
					}
					if (tgts[i] != recvs[i]) {
						exit 1
					}
				}
				print param
				exit
			}' /dev/null)" && log_info "$method Route: $3: $path$query"
		return
		;;
	esac

	[ "$path" != "$2" ] && return 1
	"$3" && log_info "$method Route: $3: $path$query"
}

# $1 - Method
# $2 - Handler
catchall() {
	[ "$method" != "$1" ] && return 1
	"$2" && log_info "Catchall: $2: $path$query"
}

fallback() {
	respond_head && log_info "Fallback: $path$query"
}

###############################################################################
# Consumer code
###############################################################################

index() {
	# TODO: Most likely bad logic because this will render the todo list for
	# users have a invalid session cookie
	printf "
		SELECT json_object('todos', (SELECT json_group_array(json_object('id', T.id, 'content', T.todo)) FROM todo T
		INNER JOIN user U ON T.user_id = U.id
		INNER JOIN user_session US ON U.id = US.user_id
		WHERE US.id = %d), 'user', %d)" "$(cookie session_id)" "$(cookie session_id)" |
		sqlite3 "$DATABASE" |
		j2 -f json ./templates/index.html - |
		respond_html
}

login() {
	j2 ./templates/login.html | respond_html
}

login_post() {
	if [ -z "$(sqlite3 "$DATABASE" "SELECT 1 FROM user WHERE email = '$(data email)' AND password = '$(data password)'")" ]; then
		email=$(data email) password=$(data password) login
		return
	fi

	# 604800 seconds = 1 week
	add_field 'Set-Cookie' "session_id=$(printf "INSERT INTO user_session(user_id) VALUES ((SELECT id FROM user WHERE email = '%s')) RETURNING id" "$(data email)" | sqlite3 "$DATABASE"); HttpOnly; Max-Age=604800"
	redirect /
}

logout() {
	printf 'DELETE FROM user_session WHERE id = %d' "$(cookie session_id)" | sqlite3 "$DATABASE"
	add_field 'Set-Cookie' 'session_id=; Max-Age: 0'
	redirect /
}

signup() {
	j2 ./templates/signup.html | respond_html
}

signup_post() {
	if test -z \
		"$(email="$(data email)" password="$(data password)" confirm_password="$(data confirm_password)" \
			perl -e '
				if ($ENV{password} ne $ENV{confirm_password}) {
					exit;
				}
				printf "INSERT INTO user(email, password) VALUES ('\''%s'\'', '\''%s'\'') RETURNING id", $ENV{email}, $ENV{password};
			' | sqlite3 "$DATABASE")"; then
		email=$(data email) password=$(data password) confirm_password=$(data confirm_password) signup
		return
	fi
	redirect /login
}

add_todo() {
	printf "INSERT INTO todo(todo, user_id) VALUES ('%s', (SELECT user_id FROM user_session WHERE id = %d))" "$(data todo)" "$(cookie session_id)" | sqlite3 "$DATABASE"
	redirect /
}

# $1 - Path parameter: Todo id
edit_todo_get() {
	[ -z "$1" ] && return 1

	sqlite3 "$DATABASE" "SELECT json_object('id', id, 'content', todo) FROM todo WHERE id = '$1'" |
		j2 -f json ./templates/_edit.html - |
		respond_html
}

# $1 - Path parameter: Todo id
edit_todo() {
	[ -z "$1" ] && return 1

	sqlite3 "$DATABASE" "UPDATE todo SET todo = '$(data content)' WHERE id = '$1'"
	redirect /
}

delete_todo() {
	[ -z "$1" ] && return 1

	sqlite3 "$DATABASE" "DELETE FROM todo WHERE id = '$1'"
	redirect /
}

false ||
	route GET / index ||
	route GET /login login ||
	route POST /login login_post ||
	route GET /signup signup ||
	route POST /signup signup_post ||
	route GET /logout logout ||
	route POST / add_todo ||
	route GET /:id/edit edit_todo_get ||
	route POST /:id/edit edit_todo ||
	route GET /:id/delete delete_todo ||
	catchall GET serve_static ||
	catchall GET serve_404 ||
	fallback
