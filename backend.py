from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from jose import JWTError, jwt
from datetime import datetime, timedelta, date
from typing import Optional
import pymysql
import os
import hashlib
import random
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Airline Reservation API")

# CORS - Allow frontend to call backend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# database connection - logic that connects to MySQL database on local pc
def get_db_connection():
    try:
        return pymysql.connect(
            host='localhost',
            user='root',
            password=os.getenv('MYSQL_PASSWORD', 'YOUR_PASSWORD'),
            database='skyvoyage',
            cursorclass=pymysql.cursors.DictCursor
        )
    except pymysql.err.OperationalError as e:
        if len(e.args) > 0 and e.args[0] == 1049:
            raise HTTPException(status_code=500, detail="Database 'skyvoyage' not found. Please execute SkyVoyageFinished.sql in MySQL.")
        raise

# hashing algorithm using hashlib
# controls the hashing for user passwords and also the JWT token key
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-min-32-characters-long")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def serialize_row(row):
    for key, value in row.items():
        if isinstance(value, (datetime, date, timedelta)):
            row[key] = str(value)
    return row

# Pydantic Models
class LoginRequest(BaseModel):
    username: str
    password: str

class RegisterRequest(BaseModel):
    first_name: str
    last_name: str
    email: str
    phone_number: str
    password: str
    dob: str

class EmployeeRequest(BaseModel):
    first_name: str
    last_name: str
    email: str
    phone_number: str
    password: str
    job_title: str
    supervisor_id: Optional[str] = None

class Token(BaseModel):
    access_token: str
    token_type: str
    role: str
    user_id: str

class BookingRequest(BaseModel):
    pass_id: str
    flight_num: str
    seat_number: str
    price: float
    agent_id: Optional[str] = None

class BaggageRequest(BaseModel):
    booking_id: str
    baggage_type: str
    weight: float

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

# ROUTES

@app.get("/")
def root():
    return {"message": "Airline Reservation API", "status": "running"}

@app.post("/api/auth/login", response_model=Token)
def login(credentials: LoginRequest):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            sql = """
                SELECT u.user_id, u.first_name, u.email, u.password_hash,
                       CASE 
                           WHEN p.passenger_id IS NOT NULL THEN 'passenger'
                           WHEN e.job_title = 'Manager' THEN 'admin'
                           WHEN e.job_title = 'Agent' THEN 'agent'
                           WHEN e.employee_id IS NOT NULL THEN 'crew'
                           ELSE 'passenger'
                       END as role
                FROM users u
                LEFT JOIN passengers p ON u.user_id = p.passenger_id
                LEFT JOIN employees e ON u.user_id = e.employee_id
                WHERE u.email = %s OR u.first_name = %s
                LIMIT 1
            """
            cursor.execute(sql, (credentials.username, credentials.username))
            result = cursor.fetchone()
            
            if not result or result['password_hash'] != hash_password(credentials.password):
                raise HTTPException(status_code=401, detail="Invalid credentials")
            
            access_token = create_access_token(
                data={"sub": result['user_id'], "role": result['role']}
            )
            
            return {
                "access_token": access_token,
                "token_type": "bearer",
                "role": result['role'],
                "user_id": result['user_id']
            }
    finally:
        conn.close()

@app.post("/api/auth/register")
def register_passenger(user_data: RegisterRequest):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            user_id = f"U{random.randint(100000000, 999999999)}"
            hashed_pw = hash_password(user_data.password)
            
            sql_user = """
                INSERT INTO users (user_id, first_name, last_name, email, password_hash, phone_number)
                VALUES (%s, %s, %s, %s, %s, %s)
            """
            cursor.execute(sql_user, (user_id, user_data.first_name, user_data.last_name, user_data.email, hashed_pw, user_data.phone_number))
            
            sql_pass = """
                INSERT INTO passengers (passenger_id, dob)
                VALUES (%s, %s)
            """
            cursor.execute(sql_pass, (user_id, user_data.dob))
            
        conn.commit()
        return {"message": "Account created successfully", "user_id": user_id}
    except pymysql.MySQLError as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Registration failed. Email may already exist.")
    finally:
        conn.close()

@app.get("/api/flights/search")
def search_flights():
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.callproc('get_public_flights')
            results = cursor.fetchall()
            flights = [serialize_row(row) for row in results]
            return {"flights": flights}
    finally:
        conn.close()

@app.get("/api/users/profile/{user_id}")
def get_user_profile(user_id: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            sql = """
                SELECT u.user_id, u.first_name, u.last_name, u.email, u.phone_number, p.dob 
                FROM users u
                LEFT JOIN passengers p ON u.user_id = p.passenger_id
                WHERE u.user_id = %s
            """
            cursor.execute(sql, (user_id,))
            user_info = cursor.fetchone()
            if not user_info:
                raise HTTPException(status_code=404, detail="User not found")
            return serialize_row(user_info)
    finally:
        conn.close()

@app.get("/api/bookings/my-bookings/{user_id}")
def get_my_bookings(user_id: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.callproc('get_my_bookings', [user_id])
            results = cursor.fetchall()
            bookings = [serialize_row(row) for row in results]
            return {"bookings": bookings}
    finally:
        conn.close()

@app.post("/api/bookings")
def create_booking(booking: BookingRequest):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            booking_id = f"BKG{random.randint(100000, 999999)}"
            
            sql = """
                INSERT INTO bookings (booking_id, status_value, seat_number, price, flight_num, pass_id, agent_identification)
                VALUES (%s, 'Confirmed', %s, %s, %s, %s, %s)
            """
            cursor.execute(sql, (
                booking_id, 
                booking.seat_number, 
                booking.price, 
                booking.flight_num, 
                booking.pass_id, 
                booking.agent_id
            ))
        conn.commit()
        return {"message": "Booking successful", "booking_id": booking_id}
    except pymysql.MySQLError as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Booking failed: {str(e)}")
    finally:
        conn.close()

@app.put("/api/bookings/cancel/{booking_id}")
def cancel_booking(booking_id: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            # First fetch the booking to confirm it exists and get the price
            cursor.execute("SELECT price, status_value FROM bookings WHERE booking_id = %s", (booking_id,))
            booking = cursor.fetchone()
            
            if not booking:
                raise HTTPException(status_code=404, detail="Booking not found")
                
            if booking['status_value'] == 'Cancelled':
                raise HTTPException(status_code=400, detail="Booking is already cancelled")
                
            # Perform the cancellation update
            sql = "UPDATE bookings SET status_value = 'Cancelled' WHERE booking_id = %s"
            cursor.execute(sql, (booking_id,))
            
        conn.commit()
        return {"message": f"Booking {booking_id} cancelled. Refund of ${booking['price']} initiated."}
    except pymysql.MySQLError as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Failed to cancel booking: {str(e)}")
    finally:
        conn.close()

@app.get("/api/baggage/{pass_id}")
def get_passenger_baggage(pass_id: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            sql = """
                SELECT b.booking_id, b.baggage_id, b.tag_id, b.baggage_type, b.weight, bk.flight_num
                FROM baggage b
                JOIN bookings bk ON b.booking_id = bk.booking_id
                WHERE bk.pass_id = %s
            """
            cursor.execute(sql, (pass_id,))
            return {"baggage": cursor.fetchall()}
    finally:
        conn.close()

@app.post("/api/baggage")
def add_baggage(baggage: BaggageRequest):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            baggage_id = f"BAG{random.randint(100000, 999999)}"
            tag_id = f"TAG{random.randint(100000, 999999)}"
            
            sql = """
                INSERT INTO baggage (booking_id, baggage_id, tag_id, baggage_type, weight)
                VALUES (%s, %s, %s, %s, %s)
            """
            cursor.execute(sql, (baggage.booking_id, baggage_id, tag_id, baggage.baggage_type, baggage.weight))
        conn.commit()
        return {"message": "Baggage added successfully"}
    except pymysql.MySQLError as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Failed to add baggage: {str(e)}")
    finally:
        conn.close()

@app.get("/api/crew/schedule/{employee_id}")
def get_crew_schedule(employee_id: str):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.callproc('get_crew_schedule', [employee_id])
            results = cursor.fetchall()
            schedule = [serialize_row(row) for row in results]
            return {"schedule": schedule}
    finally:
        conn.close()

@app.get("/api/admin/flights")
def get_all_flights():
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.callproc('get_all_flight_details')
            results = cursor.fetchall()
            flights = [serialize_row(row) for row in results]
            return {"flights": flights}
    finally:
        conn.close()

@app.post("/api/admin/employees")
def create_employee(emp: EmployeeRequest):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            user_id = f"U{random.randint(100000000, 999999999)}"
            hashed_pw = hash_password(emp.password)
            
            sql_user = """
                INSERT INTO users (user_id, first_name, last_name, email, password_hash, phone_number)
                VALUES (%s, %s, %s, %s, %s, %s)
            """
            cursor.execute(sql_user, (user_id, emp.first_name, emp.last_name, emp.email, hashed_pw, emp.phone_number))
            
            sql_emp = """
                INSERT INTO employees (employee_id, job_title, supervisor_id)
                VALUES (%s, %s, %s)
            """
            sup_id = emp.supervisor_id if emp.supervisor_id else None
            cursor.execute(sql_emp, (user_id, emp.job_title, sup_id))
            
        conn.commit()
        return {"message": "Employee created successfully", "employee_id": user_id}
    except pymysql.MySQLError as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Failed to create employee: {str(e)}")
    finally:
        conn.close()

@app.get("/api/admin/{table_name}")
def get_admin_table(table_name: str):
    allowed_tables = {
        "routes": "routes",
        "aircraft": "aircraft",
        "maintenance": "maintenance_events",
        "employees": "employees",
        "crew-assignments": "flight_crew",
        "flight-logs": "flight_report_logs"
    }
    
    if table_name not in allowed_tables:
        raise HTTPException(status_code=404, detail="Table not found")
        
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"SELECT * FROM {allowed_tables[table_name]}")
            results = cursor.fetchall()
            return {"data": [serialize_row(row) for row in results]}
    finally:
        conn.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)