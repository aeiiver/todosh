# todosh

Can you read this out loud:

<hr/>
<div style="font-size: 120%; font-weight: bold; text-align: center">DO NOT DEPLOY THIS APPLICATION!!!</div>
<hr/>

Ok, we're good.

### What is this?

`todosh` is a simple todo list application. It is written in POSIX Shell for
learning purposes (don't ask me "Why Shell?"). The idea was to sketch out
roughly the edges of what makes a web backend not suck to use so that I have a better
understanding of how to implement an actual one in a real programming language.

I'm not actually sure if the shell scripts is entirely POSIX-compliant but at
least I didn't experienced any issues with
[Dash](https://en.wikipedia.org/wiki/Almquist_shell#dash). Also, there are some
`awk` and `sed` inlined scripts which I didn't even bother checking.

I don't like the database part of the application as it is right now, and I
didn't know where I was going with the `/database.sh` script. It just looks
scuffed to me.

### Dependencies

##### Server

- awk `5.3.0`
- cat: [coreutils `9.4`](https://www.gnu.org/software/coreutils/coreutils.html)
- dash `0.5.12`
- mimetype: Perl module [File::MimeInfo `0.33`](https://metacpan.org/pod/File::MimeInfo)
- ncat: [nmap `7.94`](https://nmap.org/)
- perl `5.38`
- sed `4.9`

##### Database

- sqlite3: [sqlite `3.44.0`](https://www.sqlite.org/index.html)

##### Template engine

- j2: [j2cli `v0.3.12b`](https://github.com/kolypto/j2cli)

### How to run

Environment variables are set in `/.env`.

```sh
# Create and migrate the database
./database.sh migrate ./migrations/0001_init.sql

# Run the server
./server.sh
```
