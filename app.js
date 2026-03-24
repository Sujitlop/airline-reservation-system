const API_BASE_URL = "http://127.0.0.1:8000/api";

// Login Page
function initLoginPage() {
    const form = document.getElementById("loginForm");
    if(!form) return;

    form.addEventListener("submit", async (e) => {
        e.preventDefault();

        const username = document.getElementById("username").value.trim();
        const password = document.getElementById("password").value.trim();

        try {
            const response = await fetch(`${API_BASE_URL}/auth/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username, password })
            });

            if (!response.ok) {
                throw new Error("Invalid credentials");
            }

            const data = await response.json();
            
            sessionStorage.setItem("ars_user", JSON.stringify({
                username: username, 
                role: data.role,
                user_id: data.user_id,
                token: data.access_token
            }));
            
            // Redirect to the role specific dashboard
            window.location.href = `dashboard-${data.role}.html`;
            
        } catch (error) {
            alert(error.message);
        }
    });
}

function initRegisterPage() {
    const form = document.getElementById("registerForm");
    if (!form) return;

    form.addEventListener("submit", async (e) => {
        e.preventDefault();

        const payload = {
            first_name: document.getElementById("regFirstName").value.trim(),
            last_name: document.getElementById("regLastName").value.trim(),
            email: document.getElementById("regEmail").value.trim(),
            phone_number: document.getElementById("regPhone").value.trim(),
            password: document.getElementById("regPassword").value.trim(),
            dob: document.getElementById("regDob").value
        };

        try {
            const response = await fetch(`${API_BASE_URL}/auth/register`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            if (!response.ok) {
                const errData = await response.json();
                throw new Error(errData.detail || "Registration failed");
            }

            alert("Account created successfully! You can now log in.");
            window.location.reload(); 
            
        } catch (error) {
            alert(error.message);
        }
    });
}

// Dashboard Pages
function initDashboard() {
    const userRaw = sessionStorage.getItem("ars_user");
    const userName = document.getElementById("userName");

    if(!userName) return; // Not a dashboard page

    if(!userRaw){
        window.location.href = "index.html";
        return;
    }

    const user = JSON.parse(userRaw);
    userName.textContent = user.username;

    if (user.role === 'passenger') loadPassengerData(user);
    if (user.role === 'admin') loadAdminData(user);
    if (user.role === 'crew') loadCrewData(user);
    if (user.role === 'agent') loadAgentData(user);

    const logoutBtn = document.getElementById("logoutBtn");
    if(logoutBtn){
        logoutBtn.addEventListener("click", () => {
            sessionStorage.removeItem("ars_user");
            window.location.href = "index.html";
        });
    }
}

async function loadPassengerData(user) {
    try {
        const res = await fetch(`${API_BASE_URL}/users/profile/${user.user_id}`);
        if (res.ok) {
            const profile = await res.json();
            if(document.getElementById('profileUserId')) document.getElementById('profileUserId').textContent = profile.user_id;
            if(document.getElementById('profileName')) document.getElementById('profileName').textContent = `${profile.first_name} ${profile.last_name}`;
            if(document.getElementById('profileEmail')) document.getElementById('profileEmail').textContent = profile.email;
            if(document.getElementById('profilePhone')) document.getElementById('profilePhone').textContent = profile.phone_number;
            if(document.getElementById('profileDob')) document.getElementById('profileDob').textContent = profile.dob || '--';
        } else {
            if(document.getElementById('profileUserId')) document.getElementById('profileUserId').textContent = user.user_id;
            if(document.getElementById('profileName')) document.getElementById('profileName').textContent = user.username;
        }
    } catch (e) { 
        console.error(e); 
        if(document.getElementById('profileUserId')) document.getElementById('profileUserId').textContent = user.user_id;
        if(document.getElementById('profileName')) document.getElementById('profileName').textContent = user.username;
    }

    try {
        const res = await fetch(`${API_BASE_URL}/flights/search`);
        if (res.ok) {
            const data = await res.json();
            const tbody = document.getElementById('publicFlightsTable');
            if (tbody) {
                tbody.innerHTML = ''; 
                data.flights.forEach(f => {
                    tbody.innerHTML += `<tr>
                        <td>${f.flight_number}</td>
                        <td>${f.origin}</td>
                        <td>${f.destination}</td>
                        <td>${f.departure_date}</td>
                        <td>${f.departure_time}</td>
                        <td>${f.arrival_time}</td>
                        <td><span class="status-${f.flight_status}">${f.flight_status}</span></td>
                    </tr>`;
                });
            }
        }
    } catch (e) { console.error(e); }

    try {
        const res = await fetch(`${API_BASE_URL}/bookings/my-bookings/${user.user_id}`);
        if (res.ok) {
            const data = await res.json();
            const tbody = document.getElementById('myBookingsTable');
            if (tbody) {
                tbody.innerHTML = ''; 
                if(data.bookings.length === 0) tbody.innerHTML = '<tr><td colspan="8" class="placeholder">No bookings found.</td></tr>';
                data.bookings.forEach(b => {
                    tbody.innerHTML += `<tr>
                        <td>${b.booking_id}</td>
                        <td>${b.flight_number}</td>
                        <td>${b.origin} &rarr; ${b.destination}</td>
                        <td>${b.departure_date}</td>
                        <td>${b.seat_number}</td>
                        <td><span class="status-${b.booking_status === 'Confirmed' ? 'Departed' : 'Cancelled'}">${b.booking_status}</span></td>
                        <td>$${b.price}</td>
                        <td>
                            ${b.booking_status !== 'Cancelled' 
                                ? `<button class="btn-secondary" onclick="window.cancelPassengerBooking('${b.booking_id.trim()}')">Cancel</button>` 
                                : '---'}
                        </td>
                    </tr>`;
                });
            }
        }
    } catch (e) { console.error(e); }

    try {
        const res = await fetch(`${API_BASE_URL}/baggage/${user.user_id}`);
        if (res.ok) {
            const data = await res.json();
            const tbody = document.getElementById('passengerBaggageTable');
            if (tbody) {
                tbody.innerHTML = ''; 
                if(data.baggage.length === 0) tbody.innerHTML = '<tr><td colspan="5" class="placeholder">No baggage found.</td></tr>';
                data.baggage.forEach(b => {
                    tbody.innerHTML += `<tr>
                        <td>${b.booking_id}</td>
                        <td>${b.flight_num}</td>
                        <td>${b.tag_id}</td>
                        <td>${b.baggage_type}</td>
                        <td>${b.weight} lbs</td>
                    </tr>`;
                });
            }
        }
    } catch (e) { console.error(e); }

    const passBookingForm = document.getElementById('passengerBookingForm');
    if (passBookingForm) {
        passBookingForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const payload = {
                pass_id: user.user_id,
                flight_num: document.getElementById('passFlightNum').value.trim(),
                seat_number: document.getElementById('passSeatNum').value.trim(),
                price: parseFloat(document.getElementById('passPrice').value),
                agent_id: null
            };
            await submitBooking(payload);
        });
    }

    const baggageForm = document.getElementById('addBaggageForm');
    if (baggageForm) {
        baggageForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const payload = {
                booking_id: document.getElementById('bagBookingId').value.trim(),
                baggage_type: document.getElementById('bagType').value,
                weight: parseFloat(document.getElementById('bagWeight').value)
            };
            try {
                const res = await fetch(`${API_BASE_URL}/baggage`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                if (!res.ok) {
                    const err = await res.json();
                    throw new Error(err.detail);
                }
                alert("Baggage added!");
                window.location.reload();
            } catch (error) {
                alert(error.message);
            }
        });
    }
}

async function loadAgentData(user) {
    try {
        const res = await fetch(`${API_BASE_URL}/admin/flights`);
        if (res.ok) {
            const data = await res.json();
            const tbody = document.getElementById('staffFlightTable');
            if (tbody) {
                tbody.innerHTML = ''; 
                data.flights.forEach(f => {
                    tbody.innerHTML += `<tr>
                        <td>${f.flight_number}</td>
                        <td>${f.origin} &rarr; ${f.destination}</td>
                        <td>${f.departure_date}</td>
                        <td>${f.departure_time}</td>
                        <td>${f.arrival_time}</td>
                        <td>${f.gate || '--'}</td>
                        <td><span class="status-${f.flight_status}">${f.flight_status}</span></td>
                        <td>${f.aircraft_model || '--'}</td>
                        <td>${f.aircraft_capacity || '--'}</td>
                    </tr>`;
                });
            }
        }
    } catch (e) { console.error(e); }

    const agentBookingForm = document.getElementById('createBookingForm');
    if (agentBookingForm) {
        agentBookingForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const inputs = agentBookingForm.querySelectorAll('input');
            const payload = {
                pass_id: inputs[0].value.trim(),
                flight_num: inputs[1].value.trim(),
                seat_number: inputs[2].value.trim(),
                price: parseFloat(inputs[3].value),
                agent_id: user.user_id
            };
            await submitBooking(payload);
        });
    }
}

async function submitBooking(payload) {
    try {
        const res = await fetch(`${API_BASE_URL}/bookings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        if (!res.ok) {
            const err = await res.json();
            throw new Error(err.detail);
        }
        alert("Booking created successfully!");
        window.location.reload();
    } catch (error) {
        alert(error.message); 
    }
}

async function loadCrewData(user) {
    if(document.getElementById('crewId')) document.getElementById('crewId').textContent = user.user_id;
    if(document.getElementById('crewName')) document.getElementById('crewName').textContent = user.username;

    try {
        const res = await fetch(`${API_BASE_URL}/crew/schedule/${user.user_id}`);
        if (res.ok) {
            const data = await res.json();
            const tbody = document.getElementById('crewScheduleTable');
            if (tbody) {
                tbody.innerHTML = ''; 
                if(data.schedule.length === 0) tbody.innerHTML = '<tr><td colspan="9" class="placeholder">No assigned flights.</td></tr>';
                data.schedule.forEach(s => {
                    tbody.innerHTML += `<tr>
                        <td>${s.flight_number}</td>
                        <td>${s.origin}</td>
                        <td>${s.destination}</td>
                        <td>${s.departure_date}</td>
                        <td>${s.departure_time}</td>
                        <td>${s.arrival_time}</td>
                        <td>${s.gate || '--'}</td>
                        <td><span class="status-${s.flight_status}">${s.flight_status}</span></td>
                        <td>${s.aircraft_model || '--'}</td>
                    </tr>`;
                });
            }
        }
    } catch (e) { console.error(e); }
}

async function loadAdminData(user) {
    try {
        const res = await fetch(`${API_BASE_URL}/admin/flights`);
        if (res.ok) {
            const data = await res.json();
            const tbody = document.getElementById('adminFlightsTable');
            if (tbody) {
                tbody.innerHTML = ''; 
                data.flights.forEach(f => {
                    tbody.innerHTML += `<tr>
                        <td>${f.flight_number}</td>
                        <td>${f.departure_date}</td>
                        <td>${f.origin}</td>
                        <td>${f.destination}</td>
                        <td>${f.gate || '--'}</td>
                        <td><span class="status-${f.flight_status}">${f.flight_status}</span></td>
                        <td>${f.route_id}</td>
                        <td>${f.aircraft_model || '--'}</td>
                    </tr>`;
                });
            }
        }
    } catch (e) { console.error(e); }

    const adminTables = [
        { endpoint: 'routes', tbodyId: 'routesTable', cols: ['route_id', 'origin', 'destination', 'estimated_duration'] },
        { endpoint: 'aircraft', tbodyId: 'aircraftTable', cols: ['tail_number', 'model', 'capacity', 'total_hours_flown'] },
        { endpoint: 'maintenance', tbodyId: 'maintenanceTable', cols: ['event_id', 'tail_num', 'event_date', 'event_description', 'technician_notes'] },
        { endpoint: 'employees', tbodyId: 'employeesTable', cols: ['employee_id', 'job_title', 'supervisor_id'] },
        { endpoint: 'crew-assignments', tbodyId: 'crewAssignmentsTable', cols: ['flight_num', 'employee_id'] },
        { endpoint: 'flight-logs', tbodyId: 'flightLogsTable', cols: ['flight_num', 'report_log'] }
    ];

    for (let table of adminTables) {
        try {
            const res = await fetch(`${API_BASE_URL}/admin/${table.endpoint}`);
            if (res.ok) {
                const json = await res.json();
                const tbody = document.getElementById(table.tbodyId);
                if (tbody) {
                    tbody.innerHTML = '';
                    if (json.data.length === 0) {
                        tbody.innerHTML = `<tr><td colspan="${table.cols.length}" class="placeholder">No records found</td></tr>`;
                    } else {
                        json.data.forEach(row => {
                            let tr = '<tr>';
                            table.cols.forEach(col => tr += `<td>${row[col] || '--'}</td>`);
                            tr += '</tr>';
                            tbody.innerHTML += tr;
                        });
                    }
                }
            }
        } catch (e) { console.error(e); }
    }

    const createEmpForm = document.getElementById('createEmployeeForm');
    if (createEmpForm) {
        createEmpForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const payload = {
                first_name: document.getElementById('empFirstName').value.trim(),
                last_name: document.getElementById('empLastName').value.trim(),
                email: document.getElementById('empEmail').value.trim(),
                phone_number: document.getElementById('empPhone').value.trim(),
                password: document.getElementById('empPassword').value.trim(),
                job_title: document.getElementById('empJobTitle').value,
                supervisor_id: document.getElementById('empSupervisor').value.trim() || null
            };
            try {
                const res = await fetch(`${API_BASE_URL}/admin/employees`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                if (!res.ok) {
                    const err = await res.json();
                    throw new Error(err.detail || "Failed to create employee");
                }
                alert("Employee created successfully!");
                window.location.reload();
            } catch (error) {
                alert(error.message);
            }
        });
    }
}

// Function to handle passenger booking cancellations
window.cancelPassengerBooking = async function(bookingId) {
    if (!confirm(`Are you sure you want to cancel booking ${bookingId}?`)) return;

    try {
        const response = await fetch(`${API_BASE_URL}/bookings/cancel/${bookingId}`, {
            method: 'PUT'
        });

        if (!response.ok) {
            const errData = await response.json();
            throw new Error(errData.detail || "Cancellation failed");
        }

        const data = await response.json();
        alert(data.message);
        
        // Reload to update the UI
        window.location.reload(); 
    } catch (error) {
        alert(error.message);
    }
};

// Initialize based on page
initLoginPage();
initRegisterPage();
initDashboard();