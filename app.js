// Mock users (replace with real API later)
const mockUsers = {
    Passenger: {password: "dba123", role: "passenger"},
    Agent: {password: "dba123", role: "agent"},
    Crew: {password: "dba123", role: "crew"},
    Admin: {password: "dba123", role: "admin"},
}

// Login Page
function initLoginPage() {
    const form = document.getElementById("loginForm");
    if(!form) return;

    form.addEventListener("submit", (e) => {
        e.preventDefault();

        const username = document.getElementById("username").value.trim();
        const password = document.getElementById("password").value.trim();

        const user = mockUsers[username];

        if (user && user.password === password){
            sessionStorage.setItem("ars_user", JSON.stringify({username, role: user.role}));
            // Redirect to the role specific dashboard
            window.location.href = `dashboard-${user.role}.html`;
        }else{
            alert("Invalid credentials");
        }
    });
}

// Dashboard Pages
function initDashboard(){
    const userRaw = sessionStorage.getItem("ars_user");
    const userName = document.getElementById("userName");

    if(!userName) return; // Not a dashboard page

    if(!userRaw){
        window.location.href = "index.html";
        return;
    }

    const user = JSON.parse(userRaw);
    userName.textContent = user.username;

    const logoutBtn = document.getElementById("logoutBtn");
    if(logoutBtn){
        logoutBtn.addEventListener("click", () => {
            sessionStorage.removeItem("ars_user");
            window.location.href = "index.html";
        });
    }
}

// Initaialize based on page
initLoginPage();
initDashboard();