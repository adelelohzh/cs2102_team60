--SQL or PL/pgSQL routines of your implementation--

--Basic Functionalities

--1. add_department
DROP PROCEDURE IF EXISTS add_department;
CREATE OR REPLACE PROCEDURE add_department
   (IN department_id INTEGER, dname VARCHAR(15))
AS $$
BEGIN
   IF (SELECT EXISTS (SELECT 1 FROM Departments d WHERE d.did = department_id)) THEN
       RAISE EXCEPTION 'Department ID already exists';
   ELSE
       INSERT INTO Departments (did, dname) VALUES (department_id, dname);
   END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE OR REPLACE FUNCTION check_did() RETURNS TRIGGER AS $$
BEGIN
   IF EXISTS (SELECT 1 FROM Departments WHERE did = NEW.did) THEN
       RAISE EXCEPTION 'Department ID already exists!';
       RETURN NULL;
   ELSE
       RETURN NEW;
   END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_did
BEFORE INSERT ON Departments
FOR EACH ROW EXECUTE FUNCTION check_did();

--2. remove_department
DROP PROCEDURE IF EXISTS remove_department;
CREATE OR REPLACE PROCEDURE remove_department
    (IN department_id INT)
AS $$
BEGIN
   IF (SELECT EXISTS (SELECT 1 FROM Departments d WHERE d.did = department_id)) THEN
       DELETE FROM Departments
       WHERE did = department_id;
   ELSE
       RAISE EXCEPTION 'Department not found';
   END IF;
END;
$$ LANGUAGE plpgsql;

--3. add_room
DROP PROCEDURE IF EXISTS add_room;
CREATE OR REPLACE PROCEDURE add_room(floorNumber INTEGER, roomNumber INTEGER, roomName VARCHAR(10), roomCapacity INTEGER, managerEid INTEGER)
AS $$
BEGIN
    IF (SELECT EXISTS (SELECT 1 FROM Meeting_Rooms m WHERE m.floor = floorNumber AND m.room = roomNumber)) THEN
        RAISE EXCEPTION 'Room already exists';
    ELSIF (SELECT EXISTS(SELECT 1 FROM Manager WHERE eid = managerEid)) THEN
        INSERT INTO Meeting_Rooms (floor, room, rname)
        VALUES (floorNumber, roomNumber, roomName);
 
        INSERT INTO Updates (date, new_cap, room, floor, eid)
        VALUES (current_date, roomCapacity, roomNumber, floorNumber, managerEid);
    ELSE
        RAISE EXCEPTION 'You are not a manager!';
    END IF;
END;
$$ LANGUAGE plpgsql;

--4. change_capacity
DROP PROCEDURE IF EXISTS change_capacity;
CREATE OR REPLACE PROCEDURE change_capacity(floorNumber INTEGER, roomNumber INTEGER, capacity INTEGER, managerEid INTEGER)
AS $$
BEGIN
   IF (SELECT EXISTS(SELECT 1 FROM Manager WHERE eid = managerEid)) THEN
       IF EXISTS(SELECT 1 FROM Updates WHERE floor = floorNumber AND room = roomNumber) THEN
           UPDATE Updates u
           SET new_cap = capacity, date = current_date
           WHERE u.room = roomNumber
           AND u.floor = floorNumber;
       ELSE
           RAISE EXCEPTION 'Room does not exist';
       END IF;
   ELSE
       RAISE EXCEPTION 'You are not a manager!';
   END IF;
END;
$$ LANGUAGE plpgsql;

--5. add_employee
DROP PROCEDURE IF EXISTS add_employee;
CREATE OR REPLACE PROCEDURE add_employee(ename TEXT, contact VARCHAR(100), kind TEXT, did INT)
AS $$
DECLARE
    employee_id INT := 0;
    newEmail TEXT := '';
BEGIN
    SELECT eid
    FROM Employees
    ORDER BY eid DESC
    LIMIT 1
    INTO employee_id;

    employee_id := employee_id + 1;
    newEmail := ename || employee_id || '@cscompany.com';

    INSERT INTO Employees (eid, ename, email, contact, resigned_date)
    VALUES (employee_id, ename, newEmail, contact, NULL);

    SELECT eid
    FROM Employees
    ORDER BY eid DESC
    LIMIT 1
    INTO employee_id;
 
    IF (kind = 'junior') THEN
        INSERT INTO Junior(eid) VALUES (employee_id);
    ELSIF (kind = 'senior') THEN
        INSERT INTO Booker(eid) VALUES (employee_id);
        INSERT INTO Senior(eid) VALUES (employee_id);
 
    ELSIF (kind = 'manager') THEN
        INSERT INTO Booker(eid) VALUES (employee_id);
        INSERT INTO Manager(eid) VALUES (employee_id); 
    ELSE
        RAISE EXCEPTION 'Invalid kind (junior, senior, manager)';
    END IF;
END;
$$ LANGUAGE plpgsql;

--6. remove_employee
DROP PROCEDURE IF EXISTS remove_employee;
CREATE OR REPLACE PROCEDURE remove_employee
    (IN employee_id INTEGER, newDate DATE)
AS $$
BEGIN
    IF (SELECT EXISTS (SELECT 1 FROM Employees e WHERE e.eid = employee_id)) THEN
        UPDATE Employees
        SET resigned_date = newDate
        WHERE eid = employee_id;
    ELSE
        RAISE EXCEPTION 'Employee does not exist';
    END IF;
END;
$$ LANGUAGE plpgsql;


--Core Functionalities

--1. search_room
DROP FUNCTION IF EXISTS search_room;
CREATE OR REPLACE FUNCTION search_room(
    input_capacity INT,
    input_date DATE,
    input_start_hour INT,
    input_end_hour INT) 
RETURNS TABLE(
    floor_num INT,
    room_num INT,
    department_id INT,
    capacity INT) 
AS $$ 
BEGIN
    RETURN QUERY
    WITH Acceptable_Meeting_Rooms AS ( 
            SELECT m.room, m.floor
            FROM (meeting_rooms m INNER JOIN Updates u ON m.floor = u.floor AND m.room = u.room)
            WHERE u.new_cap >= input_capacity),
        Booked_Rooms AS (
            SELECT s.room, s.floor
            FROM sessions s INNER JOIN meeting_rooms m 
            ON s.floor = m.floor AND s.room = m.room
            WHERE s.date = input_date AND s.time :: INT >= input_start_hour AND s.time :: INT <= input_end_hour - 1)
    SELECT a.floor AS floor_num, a.room AS room_num, l.did AS department_id, u.new_cap AS capacity
    FROM
    ((SELECT * FROM Acceptable_Meeting_Rooms 
      EXCEPT
      SELECT * FROM Booked_Rooms) a INNER JOIN Located_In l 
      ON a.floor = l.floor AND a.room = l.room) INNER JOIN Updates u 
    ON u.floor = a.floor AND u.room = a.room
    ORDER BY u.new_cap;
END;
$$ LANGUAGE plpgsql;

--2. book_room
DROP PROCEDURE IF EXISTS book_room;
CREATE OR REPLACE PROCEDURE book_room(room_num INT, floor_num INT, book_date DATE, start_hour INT, end_hour INT, booker_eid INT)
AS $$
    DECLARE booker_temp FLOAT := 0 ;
BEGIN
    SELECT h.temp FROM Health_Declaration h 
    WHERE (h.eid = booker_eid AND h.date = book_date) INTO booker_temp;
    IF (SELECT EXISTS (SELECT 1 FROM Sessions s WHERE s.floor = floor_num AND s.room = room_num AND s.date = book_date AND s.time::INT = start_hour::INT)) THEN
        IF (SELECT EXISTS(SELECT 1 FROM Approves a WHERE a.floor = floor_num AND a.room = room_num AND a.date = book_date AND a.time::INT = start_hour::INT)) THEN
            RAISE EXCEPTION 'Session already exists';
        ELSE
            DELETE FROM Sessions s WHERE (s.floor = floor_num AND s.room = room_num AND s.date = book_date AND s.time::INT = start_hour::INT);
            IF (SELECT EXISTS (SELECT 1 FROM Junior j where j.eid = booker_eid)) THEN
                RAISE EXCEPTION 'Juniors cannot make bookings';
            ELSE
                SELECT h.temp into booker_temp FROM Health_Declaration h WHERE h.eid = booker_eid and h.date = CURRENT_DATE;
                IF (booker_temp >= 37.6) THEN
                    RAISE EXCEPTION 'You cannot make a booking with a fever';
                ELSE
                    INSERT INTO Sessions(room, floor, time, date)
                    VALUES (room_num, floor_num, start_hour, book_date);
                    INSERT INTO Joins(eid, room, floor, time, date)
                    VALUES (booker_eid, room_num, floor_num, start_hour, book_date);
                   RAISE notice 'Inserting into books';
                   INSERT INTO Books(eid, room, floor, time, date)
                   VALUES (booker_eid, room_num, floor_num, start_hour, book_date);
                   RAISE notice 'Inserting into joins';
                   INSERT INTO Joins(eid, room, floor, time, date)
                   VALUES (booker_eid, room_num, floor_num, start_hour, book_date);
                END IF;
            END IF;
        END IF;
    ELSE
        IF (SELECT EXISTS (SELECT 1 FROM Junior j where j.eid = booker_eid)) THEN
            RAISE EXCEPTION 'Juniors cannot make bookings';
        ELSE
            SELECT h.temp into booker_temp FROM Health_Declaration h WHERE h.eid = booker_eid and h.date = book_date;
            IF (booker_temp >= 37.6) THEN
                RAISE EXCEPTION 'You cannot make a booking with a fever';
            ELSE
                INSERT INTO Sessions(room, floor, time, date)
                VALUES (room_num, floor_num, start_hour, book_date);
                RAISE notice 'Inserting into books';
                INSERT INTO Books(eid, room, floor, time, date)
                VALUES (booker_eid, room_num, floor_num, start_hour, book_date);
                RAISE notice 'Inserting into joins';
                INSERT INTO Joins(eid, room, floor, time, date)
                VALUES (booker_eid, room_num, floor_num, start_hour, book_date);
            END IF;
        END IF;
    END IF;
END
$$ LANGUAGE plpgsql;

--3. unbook_room
DROP PROCEDURE IF EXISTS unbook_room;
CREATE OR REPLACE PROCEDURE unbook_room(floor_num INT, room_num INT, book_date DATE, start_hour INT, end_hour INT, input_eid INT)
AS $$
    DECLARE e_id INT := -1;
BEGIN
    IF (SELECT EXISTS (SELECT 1 FROM Sessions s WHERE s.floor = floor_num AND s.room = room_num AND s.date = book_date AND s.time::INT = start_hour::INT)) THEN
        SELECT b.eid INTO e_id FROM Books b WHERE b.floor = floor_num AND b.room = room_num AND b.date = book_date AND b.time::INT = start_hour::INT;
        IF (e_id != input_eid) THEN
            RAISE EXCEPTION 'You can only delete your own bookings!';
        ELSE
            DELETE FROM Sessions s WHERE s.room = room_num AND s.floor = floor_num AND s.time = start_hour AND s.date = book_date;
        END IF;
    ELSE
        RAISE EXCEPTION 'No such session exists.';
    END IF;
END;
$$ LANGUAGE plpgsql;

--4. join_meeting
DROP PROCEDURE IF EXISTS join_meeting;
CREATE OR REPLACE PROCEDURE join_meeting(
    floorNumber INTEGER, 
    roomNumber INTEGER, 
    meetingDate DATE, 
    startHour INTEGER, 
    endHour INTEGER, 
    employeeId INTEGER) 
AS $$
BEGIN
    WHILE startHour != endHour LOOP
        IF (
            EXISTS (SELECT 1 FROM Sessions s WHERE s.room = roomNumber AND s.floor = floorNumber AND s.time = startHour AND s.date = meetingDate) AND
            EXISTS (SELECT 1 FROM Joins j WHERE j.room = roomNumber AND j.floor = floorNumber AND j.time = startHour AND j.date = meetingDate AND j.eid = employeeId)
            ) THEN
            RAISE EXCEPTION 'You have already joined this meeting';
        ELSIF (EXISTS (SELECT 1 FROM Sessions s WHERE s.room = roomNumber AND s.floor = floorNumber AND s.time = startHour AND s.date = meetingDate)) THEN
            INSERT INTO Joins(eid,room,floor,time,date) VALUES (employeeId, roomNumber, floorNumber, startHour, meetingDate);
        ELSE
            RAISE EXCEPTION 'Session does not exists!';
        END IF;
      
        IF startHour = 23 THEN
            startHour := 0;
        ELSE
            startHour := startHour + 1;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

--5. leave_meeting
DROP PROCEDURE IF EXISTS leave_meeting;
CREATE OR REPLACE PROCEDURE leave_meeting(
    floorNumber INT, 
    roomNumber INT, 
    meetingDate DATE, 
    startHour INT, 
    endHour INT, 
    employeeId INT) 
AS $$
BEGIN
    WHILE startHour != endHour LOOP
        IF (EXISTS (SELECT 1 FROM Joins j 
                    WHERE j.room = roomNumber 
                    AND j.floor = floorNumber 
                    AND j.time = startHour 
                    AND j.date = meetingDate 
                    AND j.eid = employeeId)) THEN
            DELETE FROM Joins j1
            WHERE j1.room = roomNumber
            AND j1.floor = floorNumber
            AND j1.date = meetingDate
            AND j1.time = startHour
            AND j1.eid = employeeId;
        ELSE
            RAISE EXCEPTION 'You are not in this meeting';
        END IF;
      
        IF startHour = 23 THEN
            startHour := 0;
        ELSE
            startHour := startHour + 1;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

--6. approve_meeting
DROP PROCEDURE IF EXISTS approve_meeting;
CREATE OR REPLACE PROCEDURE approve_meeting(
    floorNumber INTEGER, 
    roomNumber INTEGER, 
    meetingDate DATE, 
    startHour INTEGER, 
    endHour INTEGER, 
    managerId INTEGER) 
AS $$
BEGIN
    WHILE startHour != endHour LOOP
        IF (EXISTS (SELECT 1 FROM Sessions s WHERE s.room = roomNumber AND s.floor = floorNumber AND s.time = startHour AND s.date = meetingDate)) THEN
            IF EXISTS (SELECT 1 FROM Approves a WHERE a.room = roomNumber AND a.floor = floorNumber AND a.time = startHour AND a.date = meetingDate) THEN
                RAISE EXCEPTION 'Meeting already approved';
            ELSE
                INSERT INTO Approves (eid, room, floor, time, date) 
                VALUES (managerId, roomNumber,floorNumber,startHour,meetingDate);
            END IF;
          
            IF startHour = 23 THEN
                startHour := 0;
            ELSE
                startHour := startHour + 1;
            END IF; 
        ELSE
            RAISE EXCEPTION 'Session does not exists!';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

--Health Functionalities

--1. declare_health
DROP FUNCTION IF EXISTS declare_health;
CREATE OR REPLACE FUNCTION declare_health(id INTEGER, date1 DATE, temperature FLOAT(3)) 
RETURNS BOOLEAN 
AS $$
BEGIN
    INSERT INTO Health_Declaration(eid,date,temp) VALUES (id, date1, temperature);
    UPDATE Health_Declaration SET fever = TRUE WHERE temp > 37.5 AND eid=id AND date=date1 AND temp= temperature;
    UPDATE Health_Declaration SET fever = FALSE WHERE temp <= 37.5 AND eid=id AND date=date1 AND temp= temperature;   
    RETURN fever FROM Health_Declaration WHERE eid=id AND date=date1 AND temp= temperature;
END;
$$ LANGUAGE plpgsql;
 
DROP TRIGGER IF EXISTS add_health;
CREATE OR REPLACE FUNCTION add_health() RETURNS TRIGGER 
AS $$
BEGIN
    IF NEW.date IN (SELECT date FROM Health_Declaration WHERE eid=NEW.eid) THEN
        DELETE FROM Health_Declaration WHERE date=NEW.date AND eid=NEW.eid;
        INSERT INTO Health_Declaration VALUES (NEW.eid, NEW.date, NEW.temp);
        UPDATE Health_Declaration SET fever = TRUE WHERE NEW.temp > 37.5 AND eid=NEW.eid AND date=NEW.date AND temp= NEW.temp;
        UPDATE Health_Declaration SET fever = FALSE WHERE NEW.temp <= 37.5 AND eid=NEW.eid AND date=NEW.date AND temp= NEW.temp;
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER add_health BEFORE INSERT ON Health_Declaration FOR EACH ROW EXECUTE FUNCTION add_health();


--2. contact_tracing
DROP FUNCTION IF EXISTS contact_tracing;
CREATE OR REPLACE FUNCTION contact_tracing(id INTEGER)
RETURNS TABLE (contact_id INTEGER) 
AS $$
    DECLARE
    curs CURSOR FOR (SELECT DISTINCT j1.eid FROM (
                        (Joins j JOIN Approves a
                            ON j.room = a.room 
                            AND j.floor = a.floor 
                            AND j.time = a.time 
                            AND j.date = a.date 
                            AND j.eid = id)
                        JOIN Joins j1
                        ON  j1.room = a.room 
                        AND j1.floor = a.floor 
                        AND j1.time = a.time 
                        AND j1.date = a.date)
    WHERE j1.date BETWEEN CURRENT_DATE - INTERVAL '3 DAYS'AND CURRENT_DATE);
    r1 RECORD;
BEGIN
OPEN curs;
LOOP
    FETCH curs into r1;
        EXIT WHEN NOT FOUND;
        IF (r1.eid != id) THEN
            contact_id := r1.eid;
            RETURN NEXT;
        END IF;
END LOOP;
CLOSE curs;
RETURN;
END;
$$ LANGUAGE plpgsql;


--Admin Functionalities

--1. non_compliance
DROP FUNCTION IF EXISTS non_compliance;
CREATE OR REPLACE FUNCTION non_compliance
    (IN start_date DATE,IN end_date DATE)
RETURNS TABLE(id INTEGER, count_days INTEGER) 
AS $$
DECLARE
   days INT :=0;
BEGIN
    days := DATE_PART('day', end_date::timestamp - start_date::timestamp)+1;
    RETURN QUERY 
    WITH temp AS (
        SELECT eid, (COUNT(DISTINCT(date))::INT) AS countd 
        FROM Health_Declaration 
        WHERE date BETWEEN start_date AND end_date 
        GROUP BY eid HAVING COUNT(DISTINCT(date)) <= days)
    SELECT eid, countdays 
    FROM (
        SELECT e.eid, days-(COALESCE(t.countd, 0)) AS countdays 
        FROM Employees e LEFT OUTER JOIN temp AS t 
        ON e.eid=t.eid 
        ORDER BY countdays DESC) c 
    WHERE c.countdays <> 0;
END;
$$
LANGUAGE plpgsql;

--2. view_booking_report
DROP FUNCTION IF EXISTS view_booking_report;
CREATE OR REPLACE FUNCTION view_booking_report
    (IN startDate DATE, IN employee_id INT) 
RETURNS TABLE(floor INT, room INT, date DATE, start INT, is_approved BOOLEAN)
AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        b.floor, 
        b.room, 
        b.date, 
        b.time AS start, 
        CASE
            WHEN a.eid IS NULL
            THEN FALSE
            ELSE TRUE END AS is_approved
    FROM Books b 
    LEFT JOIN Approves a
    ON b.room = a.room AND b.floor = a.floor AND b.time = a.time AND b.date = a.date
    WHERE employee_id = b.eid
    AND startDate <= b.date
    ORDER BY b.date, b.time ASC;
END;
$$ LANGUAGE plpgsql; 

--3. view_future_meeting
DROP FUNCTION IF EXISTS view_future_meeting;
CREATE OR REPLACE FUNCTION view_future_meeting
    (IN startDate DATE, IN employee_id INT)
RETURNS TABLE(floor INT, room INT, date DATE, start INT)
AS $$
BEGIN
    RETURN QUERY
    SELECT j.floor, j.room, j.date, j.time AS start
    FROM Joins j JOIN Approves a
    ON j.room = a.room AND j.floor = a.floor AND j.time = a.time AND j.date = a.date
    WHERE employee_id = j.eid
    AND startDate <= j.date
    ORDER BY j.date, j.time ASC;
END;
$$ LANGUAGE plpgsql;

--4. view_manager_report
DROP FUNCTION IF EXISTS view_manager_report;
CREATE OR REPLACE FUNCTION view_manager_report
    (IN startDate DATE, employee_id INT)
RETURNS TABLE(floor INT, room INT, date DATE, start INT, eid INT)
AS $$
BEGIN
    RETURN QUERY
    SELECT b.floor, b.room, b.date, b.time AS start, b.eid
    FROM Books b 
    JOIN Manager m
    ON employee_id = m.eid
    JOIN Works_In w1
    ON m.eid = w1.eid
    JOIN Works_In w2
    ON b.eid = w2.eid
    LEFT JOIN Approves a
    ON b.room = a.room AND b.floor = a.floor AND b.time = a.time AND b.date = a.date
    WHERE w1.did = w2.did
    AND startDate <= b.date
    AND a.eid IS NULL
    ORDER BY b.date, b.time ASC;
END;
$$ LANGUAGE plpgsql;


-- Triggers

--Remove all bookings after capacity change
CREATE OR REPLACE FUNCTION remove_all_bookings() RETURNS TRIGGER 
AS $$
BEGIN
    DELETE SESSIONS
    WHERE room = NEW.room
    AND floor = NEW.floor
    AND date > NEW.date 

    DELETE JOINS
    WHERE room = NEW.room
    AND floor = NEW.floor
    AND date > NEW.date

    DELETE Approves
    WHERE room = NEW.room
    AND floor = NEW.floor
    AND date > NEW.date

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER remove_all_bookings()  
BEFORE UPDATE ON Updates
FOR EACH ROW EXECUTE FUNCTION remove_all_bookings();


--Check today date
CREATE OR REPLACE FUNCTION check_today_date() RETURNS TRIGGER 
AS $$
DECLARE
    today DATE;
    today_hour INT;
BEGIN
    SELECT current_date INTO today;
    RAISE notice 'Value: %', today;
    IF today < NEW.date THEN
        RETURN NEW;
    ELSIF (today = NEW.date) THEN
        SELECT CAST((SELECT TO_CHAR(now(), 'HH24')) AS INTEGER) INTO today_hour;
        RAISE notice 'Value: %', today_hour;
        IF today_hour >= NEW.time THEN
            RAISE EXCEPTION 'You can only make future bookings';
            RETURN NULL;
        ELSE
            RETURN NEW;
        END IF;
    ELSE
        RAISE EXCEPTION 'You can only make future bookings';
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER check_date
BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION check_today_date();


-- Check Department ID
CREATE TRIGGER check_did
BEFORE INSERT ON Departments
FOR EACH ROW EXECUTE FUNCTION check_did();

--Check if employee is a manager
CREATE OR REPLACE FUNCTION check_if_manager() RETURNS TRIGGER 
AS $$
BEGIN
   IF EXISTS(SELECT 1 FROM Manager WHERE eid = NEW.eid) THEN
       RETURN NEW;
   ELSE
       RAISE EXCEPTION 'You are not a manager';
       RETURN NULL;
   END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_manager
BEFORE INSERT ON Updates
FOR EACH ROW EXECUTE FUNCTION check_if_manager();
 
CREATE TRIGGER check_manager
BEFORE INSERT ON Approves
FOR EACH ROW EXECUTE FUNCTION check_if_manager();


--Check if meeting room is full
CREATE OR REPLACE FUNCTION check_if_full() RETURNS TRIGGER 
AS $$
DECLARE
    max_capacity INT := 0;
    curr_capacity INT := 0;
BEGIN
    SELECT new_cap
    FROM Updates
    WHERE room = NEW.room
    AND floor = NEW.floor
    INTO max_capacity;
 
    SELECT COUNT(*)
    FROM Joins
    WHERE room = NEW.room
    AND floor = NEW.floor
    AND date = NEW.date
    AND time = NEW.time
    INTO curr_capacity;
 
    IF (curr_capacity >= max_capacity) THEN
        RAISE EXCEPTION 'Room is already at maximum capacity';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER check_if_full
BEFORE INSERT ON Joins
FOR EACH ROW
EXECUTE FUNCTION check_if_full();


--Check if booking is approved
CREATE OR REPLACE FUNCTION check_if_approved() RETURNS TRIGGER 
AS $$
DECLARE
    managerEid INT := -1;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        SELECT eid
        FROM Approves
        WHERE room = OLD.room
        AND floor = OLD.floor
        AND date = OLD.date
        AND time = OLD.time
        INTO managerEid;
      
        IF (managerEid != -1) THEN
        RAISE EXCEPTION 'Cannot join or leave approved meeting';
            RETURN NULL;
        ELSE
            RETURN OLD;
        END IF;
    ELSE
        SELECT eid
        FROM Approves
        WHERE room = NEW.room
        AND floor = NEW.floor
        AND date = NEW.date
        AND time = NEW.time
        INTO managerEid;
      
        IF (managerEid != -1) THEN
            RAISE EXCEPTION 'Cannot join or leave approved meeting';
            RETURN NULL;
        ELSE
            RETURN NEW;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER check_if_approved
BEFORE INSERT OR UPDATE OR DELETE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_if_approved();


--Check if health declaration has fever
CREATE OR REPLACE FUNCTION check_if_fever() RETURNS TRIGGER 
AS $$
DECLARE
    hasFever BOOLEAN := false;
BEGIN
    SELECT fever
    FROM Health_Declaration
    WHERE eid = NEW.eid
    AND date = NEW.date
    INTO hasFever;
 
    IF (hasFever) THEN 
        RAISE EXCEPTION 'You cannot join a meeting with a fever';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER check_if_fever
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_if_fever();


--Check same department
CREATE OR REPLACE FUNCTION check_same_department() RETURNS TRIGGER 
AS $$
DECLARE
    booker_did INT := -1;
BEGIN
    SELECT did
    FROM Books b JOIN Works_In w
    ON b.eid = w.eid
    WHERE b.room = NEW.room 
    AND b.floor = NEW.floor
    AND b.date = NEW.date
    AND b.time = NEW.time
    INTO booker_did;

    IF ((SELECT did FROM Works_In WHERE eid = NEW.eid) != booker_did) THEN
        RAISE EXCEPTION 'You are not from the same department as the booker';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_same_department()  
BEFORE INSERT ON Approve
FOR EACH ROW EXECUTE FUNCTION check_same_department();


--Check if employee is resigned 
CREATE OR REPLACE FUNCTION check_if_resigned() RETURNS TRIGGER 
AS $$
DECLARE
    resignedDate DATE := NULL;
BEGIN
    SELECT resigned_date
    FROM Employees
    WHERE eid = NEW.eid
    INTO resignedDate;
 
    IF (resignedDate IS NOT NULL) THEN 
        RAISE EXCEPTION 'Resigned Employees cannot join/book/approve meetings!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER check_if_resigned
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_if_resigned();
 
CREATE TRIGGER check_if_resigned
BEFORE INSERT ON Books
FOR EACH ROW EXECUTE FUNCTION check_if_resigned();
 
CREATE TRIGGER check_if_resigned
BEFORE INSERT ON Approves
FOR EACH ROW EXECUTE FUNCTION check_if_resigned();


 
CREATE OR REPLACE FUNCTION check_non_compliance() RETURNS TRIGGER 
AS $$
DECLARE
    employeeId INT := -1;
BEGIN
    SELECT eid
    FROM non_compliance()
    WHERE eid = NEW.eid
    INTO employeeId;
 
    IF (employeeId != -1) THEN
RAISE EXCEPTION ‘You must complete health declaration before joining/booking/approving a room!”
RETURN NULL;
ELSE
    RETURN NEW;
END IF;
END;
$$ LANGUAGE plpgsql;
 
CREATE TRIGGER check_non_compliance
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW EXECUTE FUNCTION check_non_compliance();
 
CREATE TRIGGER check_non_compliance
BEFORE INSERT OR UPDATE ON Books
FOR EACH ROW EXECUTE FUNCTION check_non_compliance();
 
CREATE TRIGGER check_non_compliance
BEFORE INSERT OR UPDATE ON Approves
FOR EACH ROW EXECUTE FUNCTION check_non_compliance();


/*
CREATE OR REPLACE FUNCTION check_if_closeContact() RETURNS TRIGGER AS $$
DECLARE
BEGIN
    
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_if_closeContact()  
BEFORE INSERT OR UPDATES ON Joins
FOR EACH ROW EXECUTE FUNCTION check_if_closeContact();
*/