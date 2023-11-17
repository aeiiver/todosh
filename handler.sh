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
	printf '%s' "$response_fields" | sed 's/!!!/\r\n/'
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
	printf '%s' "$response_fields" | sed 's/!!!/\r\n/'
	printf '\r\n'
	cat
}

respond_head() {
	printf '%s\r\n' "$response_rqline"
	printf '%s' "$response_fields" | sed 's/!!!/\r\n/'
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
	sed -n '$s/.*'"$1"'=\([^&]*\).*/\1/p' <<-RAW
		$raw
	RAW
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
		"$3" "$(awk -vtgt="$2" -vrecv="$path" 'BEGIN { nb_tgts = split(tgt, tgts, "/"); nb_recvs = split(recv, recvs, "/"); if (nb_tgts != nb_recvs) { exit 1; } for (i = 1; i <= nb_tgts; i += 1) { if (substr(tgts[i], 1, 1) ~ /:/) { param = recvs[i]; continue; } if (tgts[i] != recvs[i]) { exit 1; } } print param; exit; }' /dev/null)" && log_info "$method Route: $3: $path$query"
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

handle_get() {
	sqlite3 "$DATABASE" "SELECT json_group_object('todos', (SELECT json_group_array(json_object('id', id, 'content', todo)) FROM todo))" |
		j2 -f json ./templates/index.html - |
		respond_html
}

handle_post() {
	sqlite3 "$DATABASE" "INSERT INTO todo(todo) VALUES ('$(data todo)')"
	redirect /
}

# $1 - Path parameter: Todo id
handle_edit_get() {
	[ -z "$1" ] && return 1

	sqlite3 "$DATABASE" "SELECT json_object('id', id, 'content', todo) FROM todo WHERE id = '$1'" |
		j2 -f json ./templates/_edit.html - |
		respond_html
}

# $1 - Path parameter: Todo id
handle_edit_post() {
	[ -z "$1" ] && return 1

	sqlite3 "$DATABASE" "UPDATE todo SET todo = '$(data content)' WHERE id = '$1'"
	redirect /
}

handle_delete_get() {
	[ -z "$1" ] && return 1

	sqlite3 "$DATABASE" "DELETE FROM todo WHERE id = '$1'"
	redirect /
}

false ||
	route GET / handle_get ||
	route POST / handle_post ||
	route GET /:id/edit handle_edit_get ||
	route POST /:id/edit handle_edit_post ||
	route GET /:id/delete handle_delete_get ||
	catchall GET serve_static ||
	catchall GET serve_404 ||
	fallback
