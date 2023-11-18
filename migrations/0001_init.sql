CREATE TABLE user (
    id        INTEGER PRIMARY KEY,
    email     TEXT UNIQUE,
    password  TEXT
);

CREATE TABLE user_session (
    id        INTEGER PRIMARY KEY,
    user_id   INTEGER REFERENCES user(id) ON DELETE CASCADE
);

CREATE TABLE todo (
    id       INTEGER PRIMARY KEY,
    todo     TEXT,
    user_id  INTEGER REFERENCES user(id) ON DELETE CASCADE
);
