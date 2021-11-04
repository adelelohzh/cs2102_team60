--CREATE DATABASE
DROP TABLE IF EXISTS Employees,
Junior,
Booker,
Senior,
Manager,
Meeting_Rooms,
Departments,
Health_Declaration,
Sessions,
Works_In,
Located_In,
Joins,
Books,
Approves,
Updates;

CREATE TABLE Employees (
    eid INTEGER,
    ename TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    contact VARCHAR(100) UNIQUE NOT NULL,
    resigned_date DATE,
    PRIMARY KEY (eid)
);

CREATE TABLE Junior (
    eid INTEGER PRIMARY KEY REFERENCES Employees(eid) ON DELETE CASCADE
);

CREATE TABLE Booker (
    eid INTEGER PRIMARY KEY REFERENCES Employees(eid) ON DELETE CASCADE
);

CREATE TABLE Senior (
    eid INTEGER PRIMARY KEY REFERENCES Booker(eid) ON DELETE CASCADE
);

CREATE TABLE Manager (
    eid INTEGER PRIMARY KEY REFERENCES Booker(eid) ON DELETE CASCADE
);

CREATE TABLE Health_Declaration (
    eid INTEGER,
    date DATE,
    temp FLOAT,
    fever BOOLEAN,
    PRIMARY KEY(eid, date),
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON DELETE CASCADE
);

CREATE TABLE Departments (
    did INTEGER,
    dname VARCHAR(30),
    PRIMARY KEY (did)
);

CREATE TABLE Meeting_Rooms (
    room INTEGER,
    floor INTEGER,
    rname VARCHAR(10),
    PRIMARY KEY (room, floor)
);

CREATE TABLE Sessions (
    room INTEGER,
    floor INTEGER,
    time INTEGER,
    date DATE,
    PRIMARY KEY (room, floor, time, date),
    FOREIGN KEY (room, floor) REFERENCES Meeting_Rooms (room, floor) ON DELETE CASCADE
);

CREATE TABLE Works_In (
    eid INTEGER REFERENCES Employees,
    did INTEGER NOT NULL,
    PRIMARY KEY (eid),
    FOREIGN KEY (did) REFERENCES Departments
);

CREATE TABLE Located_In (
    room INTEGER,
    floor INTEGER,
    did INTEGER,
    PRIMARY KEY (room, floor),
    FOREIGN KEY (did) REFERENCES Departments,
    FOREIGN KEY (room, floor) REFERENCES Meeting_Rooms (room, floor) ON DELETE CASCADE
);

CREATE TABLE Joins (
    eid INTEGER REFERENCES Employees,
    room INTEGER NOT NULL,
    floor INTEGER NOT NULL,
    time INTEGER NOT NULL,
    date DATE NOT NULL,
    PRIMARY KEY (eid, room, floor, time, date),
    FOREIGN KEY (room, floor, time, date) REFERENCES Sessions (room, floor, time, date) ON DELETE CASCADE
);

CREATE TABLE Books (
    eid INTEGER NOT NULL,
    room INTEGER,
    floor INTEGER,
    time INTEGER,
    date DATE,
    PRIMARY KEY (room, floor, time, date),
    FOREIGN KEY (room, floor, time, date) REFERENCES Sessions (room, floor, time, date) ON DELETE CASCADE
);

CREATE TABLE Approves(
    eid INTEGER NOT NULL,
    room INTEGER,
    floor INTEGER,
    time INTEGER,
    date DATE,
    PRIMARY KEY (room, floor, time, date),
    FOREIGN KEY (room, floor, time, date) REFERENCES Sessions (room, floor, time, date) ON DELETE CASCADE
);

CREATE TABLE Updates (
    date DATE,
    new_cap INTEGER,
    room INTEGER NOT NULL,
    floor INTEGER NOT NULL,
    eid INTEGER,
    PRIMARY KEY(date, room, floor, eid),
    FOREIGN KEY (eid) REFERENCES Manager ON DELETE CASCADE,
    FOREIGN KEY (room, floor) REFERENCES Meeting_Rooms (room, floor) ON DELETE CASCADE
);
