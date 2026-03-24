create database skyvoyage;
use skyvoyage;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
	user_id CHAR(10), 
    first_name VARCHAR(20), 
    last_name VARCHAR(20), 
    email VARCHAR(25), 
    password_hash VARCHAR(255),
    phone_number CHAR(10), 
    CONSTRAINT us_id_pk PRIMARY KEY (user_id),
    CONSTRAINT uniq_email UNIQUE(email)
);

DROP TABLE IF EXISTS routes;
CREATE TABLE routes (
	route_id CHAR(10), 
    origin CHAR(3), 
    destination CHAR(3), 
    estimated_duration INT, 
    CONSTRAINT route_id_pk PRIMARY KEY (route_id)
);

DROP TABLE IF EXISTS aircraft;
CREATE TABLE aircraft (
	tail_number CHAR(10), 
    model VARCHAR(20), 
    total_hours_flown INTEGER, 
    capacity INTEGER, 
    CONSTRAINT tail_number_pk PRIMARY KEY (tail_number)
);

DROP TABLE IF EXISTS passengers;
CREATE TABLE passengers (
	passenger_id CHAR(10), 
    dob DATE,
    # frequent_flyer_number INTEGER, 
    CONSTRAINT pass_foreign_key
		FOREIGN KEY (passenger_id)
        REFERENCES skyvoyage.users(user_id),
    CONSTRAINT pass_pk PRIMARY KEY (passenger_id)
);

DROP TABLE IF EXISTS flights;
CREATE TABLE flights (
	flight_number CHAR(5), 
    departure_date DATE, 
    departure_time TIME, 
    arrival_time TIME, 
    gate VARCHAR(10),
    
    # Only need these values: Scheduled, Delayed, Cancelled, Departed, Boarding, and Arrived. 
    flight_status ENUM('Scheduled', 'Delayed', 'Cancelled', 'Arrived', 'Departed', 'Boarding')
		DEFAULT 'Scheduled'
		NOT NULL,
        
    route_id CHAR(10), 
    tail_number CHAR(10),
    CONSTRAINT route_id_fk 
		FOREIGN KEY (route_id)
		REFERENCES skyvoyage.routes(route_id),
	CONSTRAINT tail_number_fk 
		FOREIGN KEY (tail_number)
		REFERENCES skyvoyage.aircraft(tail_number),
    CONSTRAINT flight_num_pk PRIMARY KEY (flight_number)
);

DROP TABLE IF EXISTS employees;
CREATE TABLE employees (
	employee_id CHAR(10), 
    job_title CHAR(20), 
    supervisor_id CHAR(10), 
    CONSTRAINT user_id_unique_key 
		FOREIGN KEY (employee_id)
		REFERENCES skyvoyage.users(user_id),
	CONSTRAINT emp_supervisor_fk
		FOREIGN KEY (supervisor_id)
        REFERENCES employees(employee_id)
        ON DELETE SET NULL, 
    CONSTRAINT empl_id_pk PRIMARY KEY (employee_id)
);

DROP TABLE IF EXISTS bookings;
CREATE TABLE bookings (
	booking_id CHAR(10), 
    booking_date TIMESTAMP, 
    status_value VARCHAR(10), 
    seat_number VARCHAR(3), 
    price DECIMAL(8,2),
    flight_num CHAR(5) NOT NULL, 
    pass_id CHAR(10) NOT NULL, 
    agent_identification CHAR(10), 
    CONSTRAINT flight_fk 
		FOREIGN KEY (flight_num) 
		REFERENCES skyvoyage.flights(flight_number),
	CONSTRAINT pass_id_fk 
		FOREIGN KEY (pass_id) 
		REFERENCES skyvoyage.passengers(passenger_id),
	CONSTRAINT agent_fk 
		FOREIGN KEY (agent_identification) 
		REFERENCES skyvoyage.employees(employee_id),
    CONSTRAINT book_id_pk PRIMARY KEY (booking_id)
);

DROP TABLE IF EXISTS baggage;
CREATE TABLE baggage (
	booking_id CHAR(10), 
    baggage_id CHAR(10), 
    tag_id CHAR(10) UNIQUE, 
    baggage_type VARCHAR(10), 
    weight DECIMAL(5,2),
    CONSTRAINT bag_tag_id_pk PRIMARY KEY (baggage_id, tag_id),
	CONSTRAINT baggage_constraint 
		FOREIGN KEY (booking_id)
		REFERENCES skyvoyage.bookings(booking_id)
        ON DELETE CASCADE
);

DROP TABLE IF EXISTS flight_report_logs;
CREATE TABLE flight_report_logs (
	flight_num CHAR(10), 
    report_log VARCHAR(20), 
    CONSTRAINT flight_num_fk 
		FOREIGN KEY (flight_num)
		REFERENCES skyvoyage.flights(flight_number)
        ON DELETE CASCADE,
    CONSTRAINT report_log_pk PRIMARY KEY (report_log)
);

DROP TABLE IF EXISTS maintenance_events;
CREATE TABLE maintenance_events (
	event_id CHAR(10), 
    event_date DATE, 
    event_description TEXT, 
    technician_notes TEXT, 
    tail_num CHAR(10),
    CONSTRAINT tail_num_fk_events
		FOREIGN KEY (tail_num)
		REFERENCES skyvoyage.aircraft(tail_number)
        ON DELETE CASCADE,
    CONSTRAINT tail_num_event_id_pk PRIMARY KEY (tail_num, event_id)
);

DROP TABLE IF EXISTS flight_crew;
CREATE TABLE flight_crew (
	flight_num CHAR(10), 
    employee_id CHAR(10), 
    CONSTRAINT flight_num_fk2
		FOREIGN KEY (flight_num)
		REFERENCES skyvoyage.flights(flight_number),
	CONSTRAINT employee_id_fk
		FOREIGN KEY (employee_id)
		REFERENCES skyvoyage.employees(employee_id),
    CONSTRAINT flight_employee_pk PRIMARY KEY (flight_num, employee_id)
);

/* This trigger will update to the current time a booking was made before entering the bookings table */
DROP TRIGGER IF EXISTS trg_booking_date_now;
DELIMITER $$
CREATE TRIGGER trg_booking_date_now
BEFORE INSERT ON skyvoyage.bookings 
FOR EACH ROW
BEGIN
	SET NEW.booking_date = CURRENT_TIMESTAMP;
END$$
DELIMITER ;

/* Update the duration of the flight using estimated dur when the plane arrives */
DROP TRIGGER IF EXISTS trg_arrival_dur_update;
DELIMITER $$
CREATE TRIGGER trg_arrival_dur_update
BEFORE INSERT ON skyvoyage.flights
FOR EACH ROW
BEGIN
	# Let's set up a variable to store the supposed destination
    DECLARE time_dur INT;

	# Make sure the plane updates the time out when it arrives.
    IF NEW.flight_status = 'Arrived' THEN
		# Grab the route_id from routes and match it to the currently arrived plane
		SELECT estimated_duration INTO time_dur FROM skyvoyage.routes r
        WHERE 
			r.route_id = NEW.route_id;
		
        # Want to update the aircraft if the plane arrived (need time_dur not null to get total hours added)
        IF time_dur IS NOT NULL AND NEW.tail_number IS NOT NULL 
        THEN 
			UPDATE skyvoyage.aircraft a # change rows in aircraft
            SET a.total_hours_flown = a.total_hours_flown + ceiling(time_dur / 60.0) # we need the lowest hours total (increment total_hours with the arrival flight
            WHERE # condition to update each row in aircraft for the plane that landed
				a.tail_number = NEW.tail_number;
		END IF;
	END IF;
END$$
DELIMITER ;
				
/* Set up a trigger that let's the customer schedule available flights */
DROP TRIGGER IF EXISTS trg_available_flights;
DELIMITER $$
CREATE TRIGGER trg_available_flights
BEFORE INSERT ON skyvoyage.bookings
FOR EACH ROW
BEGIN
	# use this value to see the current flight status
	DECLARE current_status VARCHAR(20);
    
    # save the current flight_status into current_status
    SELECT flight_status INTO current_status FROM skyvoyage.flights f
    WHERE 
		f.flight_number = NEW.flight_num;
	
    IF current_status IN ('Cancelled', 'Delayed', 'Departed') 
    THEN 
		SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = "Flight is unavailable at the moment";
	END IF;
END$$
DELIMITER ;

/* make sure ticket price is set to a limit */
DROP TRIGGER IF EXISTS trg_ticket_price;
DELIMITER $$
CREATE TRIGGER trg_ticket_price
BEFORE INSERT ON skyvoyage.bookings
FOR EACH ROW
BEGIN
	IF NEW.price < 500 THEN
		SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = "Base ticket price set at $500";
	END IF;
END$$
DELIMITER ;

/* Set up a procedure that handles canceling booking */
DROP PROCEDURE IF EXISTS proc_cancel_booking;

DELIMITER $$
CREATE PROCEDURE proc_cancel_booking (
	IN ticket_booking INT, OUT cancel_message VARCHAR(50))
	BEGIN
		DECLARE b_price DECIMAL(10,2);
        
        SELECT price INTO b_price
        FROM skyvoyage.bookings
        WHERE booking_id = ticket_booking;
        
        UPDATE skyvoyage.bookings
        SET STATUS = 'Cancelled'
        WHERE booking_id = ticket_booking; 
        
        SET cancel_message = CONCAT ('Booking ', ticket_booking, ' cancelled. Refund of $', 
			b_price, ' initiated.'
		);
	END$$
DELIMITER ;
    
/* Create views */

# to be safe, I'll use three different views for the roles of: 
# passengers, crew members, and staff when it comes to flight details

# passengers/users/public view for flight
DROP VIEW IF EXISTS v_flight_details_public;
CREATE VIEW v_flight_details_public AS
SELECT
    f.flight_number,
    f.departure_date,
    f.departure_time,
    f.arrival_time,
    f.flight_status,
    r.origin,
    r.destination
FROM flights AS f
JOIN routes AS r
    ON f.route_id = r.route_id;
    
# flight details for crew members views
DROP VIEW IF EXISTS v_flight_details_crew;
CREATE VIEW v_flight_details_crew AS
SELECT
    f.flight_number,
    f.departure_date,
    f.departure_time,
    f.arrival_time,
    f.gate,
    f.flight_status,
    r.origin,
    r.destination,
    a.model AS aircraft_model
FROM flights AS f
JOIN routes AS r
    ON f.route_id = r.route_id
LEFT JOIN aircraft AS a
    ON f.tail_number = a.tail_number;
    
# agent/staff members flight details view
DROP VIEW IF EXISTS v_flight_details_staff;
CREATE VIEW v_flight_details_staff AS
SELECT
    f.flight_number,
    f.departure_date,
    f.departure_time,
    f.arrival_time,
    f.gate,
    f.flight_status,
    r.route_id,
    r.origin,
    r.destination,
    r.estimated_duration,
    a.tail_number,
    a.model AS aircraft_model,
    a.capacity AS aircraft_capacity
FROM flights AS f
JOIN routes AS r
    ON f.route_id = r.route_id
LEFT JOIN aircraft AS a
    ON f.tail_number = a.tail_number;
    
# Booking Details — joins booking + passenger + flight + route
DROP VIEW IF EXISTS v_booking_details;
CREATE VIEW v_booking_details AS
SELECT
    b.booking_id,
    b.booking_date,
    b.status_value AS booking_status,
    b.seat_number,
    b.price,
    u.first_name AS passenger_fname,
    u.last_name AS passenger_lname,
    u.email AS passenger_email,
    p.passenger_id,
    f.flight_number,
    f.departure_date,
    f.departure_time,
    f.flight_status,
    r.origin,
    r.destination,
    ag.first_name AS agent_fname,
    ag.last_name AS agent_lname
FROM bookings AS b
JOIN passengers AS p
    ON b.pass_id = p.passenger_id
JOIN users AS u
    ON p.passenger_id = u.user_id
JOIN flights AS f
    ON b.flight_num = f.flight_number
JOIN routes AS r
    ON f.route_id = r.route_id
LEFT JOIN users AS ag
    ON b.agent_identification = ag.user_id;

# Crew Schedule — shows employee flight assignments with details
DROP VIEW IF EXISTS v_crew_schedule;
CREATE VIEW v_crew_schedule AS
SELECT
    fc.employee_id,
    u.first_name,
    u.last_name,
    e.job_title,
    f.flight_number,
    f.departure_date,
    f.departure_time,
    f.arrival_time,
    f.gate,
    f.flight_status AS flight_status,
    r.origin,
    r.destination
FROM flight_crew AS fc
JOIN employees AS e
    ON fc.employee_id = e.employee_id
JOIN users AS u
    ON e.employee_id = u.user_id
JOIN flights AS f
    ON fc.flight_num = f.flight_number
JOIN routes AS r
    ON f.route_id = r.route_id;

/* Create roles for the passengers, crew members, and agents/staff */
DROP ROLE IF EXISTS passenger_role;
DROP ROLE IF EXISTS crew_role;
DROP ROLE IF EXISTS staff_role;

CREATE ROLE passenger_role;
CREATE ROLE crew_role;
CREATE ROLE staff_role;

/* Create security for users */
DROP PROCEDURE IF EXISTS skyvoyage.get_my_bookings;

DELIMITER $$
CREATE PROCEDURE skyvoyage.get_my_bookings(IN proc_user_id VARCHAR(10))
BEGIN
    SELECT *
    FROM v_booking_details
    WHERE passenger_id = proc_user_id;
END$$
DELIMITER ;

# create procedure for public_flights
DROP PROCEDURE IF EXISTS skyvoyage.get_public_flights;

DELIMITER $$
CREATE PROCEDURE skyvoyage.get_public_flights()
BEGIN
    SELECT *
    FROM v_flight_details_public;
END$$
DELIMITER ;

# Let's let passengers have privilege to see public fights
GRANT EXECUTE ON PROCEDURE skyvoyage.get_public_flights TO passenger_role;

/* Create security check for crew members */
DROP PROCEDURE IF EXISTS skyvoyage.get_crew_schedule;

DELIMITER $$
CREATE PROCEDURE skyvoyage.get_crew_schedule(IN proc_crew_id CHAR(10))
BEGIN
    SELECT v.*
    FROM v_flight_details_crew v
    JOIN flight_crew fc
        ON v.flight_number = fc.flight_num
    WHERE fc.employee_id = proc_crew_id;
END$$
DELIMITER ;

/*
SHOW PROCEDURE STATUS
WHERE Db = 'skyvoyage'
  AND Name = 'get_crew_schedule';*/

/* Just some security measures to make sure crew_members only have access to
the procedure get_crew_schedule */
GRANT EXECUTE ON PROCEDURE skyvoyage.get_crew_schedule TO crew_role;

/* Create security check for flight detaiils */
# staff can be trusted
DROP PROCEDURE IF EXISTS skyvoyage.get_all_flight_details;

DELIMITER $$
CREATE PROCEDURE skyvoyage.get_all_flight_details()
BEGIN
    SELECT *
    FROM v_flight_details_staff;
END$$
DELIMITER ;

/* Give access to staff_role */
GRANT EXECUTE ON PROCEDURE skyvoyage.get_all_flight_details TO staff_role;
  


# User dummy data
INSERT INTO skyvoyage.users VALUES
('U000000001','Alice','Smith','alice@airline.com','password123','3185551111'),
('U000000002','Bob','Johnson','bob@airline.com','password123','3185552222'),
('U000000003','Carol','Williams','carol@airline.com','password123','3185553333'),
('U000000004','Dave','Brown','dave@airline.com','password123','3185554444'),
('U000000005','Eve','Davis','eve@airline.com','password123','3185555555');


# Routes dummy data
INSERT INTO skyvoyage.routes VALUES
('RTE0000001','DFW','ATL','2'),
('RTE0000002','ATL','JFK','3'),
('RTE0000003','JFK','LAX','6');

# Aircraft dummy data
INSERT INTO skyvoyage.aircraft VALUES
('TAIL000001','Boeing 737',12000,160),
('TAIL000002','Airbus A320',9800,150),
('TAIL000003','Boeing 787',15000,240);

# Passenger dummy data
INSERT INTO skyvoyage.passengers VALUES
('U000000001','1999-05-21'),
('U000000002','2001-08-12'),
('U000000003','1995-02-03');

# employee dummy data
INSERT INTO skyvoyage.employees VALUES
('U000000004','Manager',NULL),
('U000000005','Agent','U000000004');

# flight dummy data
INSERT INTO skyvoyage.flights VALUES
('F1001','2026-03-10','08:00:00','10:10:00','A12','Scheduled','RTE0000001','TAIL000001'),
('F1002','2026-03-10','12:00:00','14:30:00','B07','Scheduled','RTE0000002','TAIL000002'),
('F1003','2026-03-11','09:00:00','15:00:00','C03','Scheduled','RTE0000003','TAIL000003');

# booking dummy data
INSERT INTO skyvoyage.bookings VALUES
('BKG000001',NOW(),'Confirmed','12A',599.99,'F1001','U000000001','U000000005'),
('BKG000002',NOW(),'Confirmed','14C',649.99,'F1002','U000000002','U000000005'),
('BKG000003',NOW(),'Confirmed','22B',799.99,'F1003','U000000003','U000000005');

# baggage dummy data
INSERT INTO skyvoyage.baggage VALUES
('BKG000001','BAG000001','TAG000001','Checked',42.5),
('BKG000001','BAG000002','TAG000002','CarryOn',18.0),
('BKG000002','BAG000003','TAG000003','Checked',38.2);

# flight_log dummy data
INSERT INTO skyvoyage.flight_report_logs VALUES
('F1001','OnTime'),
('F1002','MinorDelay'),
('F1003','SmoothFlight');

# maintenance_events dummy data
INSERT INTO skyvoyage.maintenance_events VALUES
('EVT000001','2026-02-01','Routine inspection','All systems OK','TAIL000001'),
('EVT000002','2026-02-05','Engine check','Replaced filter','TAIL000002');

# flight_crew dummy data
INSERT INTO skyvoyage.flight_crew VALUES
('F1001','U000000004'),
('F1001','U000000005'),
('F1002','U000000004'),
('F1003','U000000004');

SET FOREIGN_KEY_CHECKS = 0;