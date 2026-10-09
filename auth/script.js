// =========================
// LOGIN ELEMENTS
// =========================
const loginForm = document.getElementById("loginForm");
const loginEmail = document.getElementById("loginEmail");
const loginPassword = document.getElementById("loginPassword");
const loginError = document.getElementById("loginError");
const loginSubmit = document.getElementById("loginSubmit");
const togglePassword = document.getElementById("togglePassword");

// Show or hide the login password
if (togglePassword && loginPassword) {
    togglePassword.addEventListener("click", function () {
        const showPassword = loginPassword.type === "password";

        loginPassword.type = showPassword ? "text" : "password";
        togglePassword.setAttribute(
            "aria-label",
            showPassword ? "Hide password" : "Show password"
        );
    });
}

// =========================
// LOGIN LOCKOUT COUNTDOWN
// =========================
let countdownTimer = null;
let lockEndsAt = 0;

function startLockCountdown(seconds) {
    clearInterval(countdownTimer);

    lockEndsAt = Date.now() + seconds * 1000;
    loginSubmit.disabled = true;

    function updateCountdown() {
        const remaining = Math.max(
            0,
            Math.ceil((lockEndsAt - Date.now()) / 1000)
        );

        const minutes = String(
            Math.floor(remaining / 60)
        ).padStart(2, "0");

        const secs = String(remaining % 60).padStart(2, "0");

        loginError.textContent =
            `Account temporarily locked. Try again in ${minutes}:${secs}.`;

        if (remaining === 0) {
            clearInterval(countdownTimer);
            lockEndsAt = 0;
            loginSubmit.disabled = false;
            loginError.textContent = "You can try logging in again now.";
        }
    }

    countdownTimer = setInterval(updateCountdown, 1000);
    updateCountdown();
}

// =========================
// LOGIN SUBMISSION
// =========================
if (loginForm) {
    loginForm.addEventListener("submit", async function (event) {
        event.preventDefault();

        if (Date.now() < lockEndsAt || loginSubmit.disabled) {
            return;
        }

        if (
            loginEmail.value.trim() === "" ||
            loginPassword.value === ""
        ) {
            loginError.textContent = "Please fill in all fields.";
            loginError.classList.add("error-pop");
            return;
        }

        loginSubmit.disabled = true;
        loginError.classList.remove("error-pop");
        loginError.textContent = "";

        try {
            const response = await fetch("login.php", {
                method: "POST",
                body: new FormData(loginForm)
            });

            const data = await response.text();

            if (response.status === 429) {
                const seconds = Number(data.trim().split("|")[1]);

                if (Number.isFinite(seconds) && seconds > 0) {
                    startLockCountdown(seconds);
                } else {
                    loginError.textContent =
                        "Account temporarily locked. Try again later.";
                }
            } else if (response.status === 401) {
                loginError.textContent = "Invalid username or password.";
                loginError.classList.add("error-pop");
            } else if (response.status === 400) {
                loginError.textContent = "Please fill in all fields.";
            } else if (response.status === 403) {
                loginError.textContent = data.trim();
            } else if (response.ok && response.redirected) {
                // Accept only the two dashboard destinations
                const destination = new URL(response.url);

                const adminDashboard = new URL(
                    "../admin/dashboard.php",
                    window.location.href
                );

                const staffDashboard = new URL(
                    "../staff/dashboard.php",
                    window.location.href
                );

                const validDashboard =
                    destination.origin === window.location.origin &&
                    (
                        destination.pathname === adminDashboard.pathname ||
                        destination.pathname === staffDashboard.pathname
                    );

                if (validDashboard) {
                    window.location.assign(destination.href);
                } else {
                    loginError.textContent =
                        "Unable to open your dashboard. Please try again.";
                }
            } else {
                loginError.textContent =
                    "Something went wrong. Please try again later.";
            }
        } catch (error) {
            loginError.textContent =
                "Unable to connect. Please try again.";
        } finally {
            if (Date.now() >= lockEndsAt) {
                loginSubmit.disabled = false;
            }
        }
    });
}

// =========================
// ORIGINAL SIGNUP SUPPORT
// Kept for the saved signup page
// =========================
const signupForm = document.getElementById("signupForm");
const signupUsername = document.getElementById("signupUsername");
const signupEmail = document.getElementById("signupEmail");
const signupPassword = document.getElementById("signupPassword");
const confirmPassword = document.getElementById("confirmPassword");
const signupError = document.getElementById("signupError");

const toggleSignupPassword = document.getElementById("toggleSignupPassword");
const toggleConfirmPassword = document.getElementById("toggleConfirmPassword");

if (toggleSignupPassword && signupPassword) {
    toggleSignupPassword.addEventListener("click", function () {
        const showPassword = signupPassword.type === "password";

        signupPassword.type = showPassword ? "text" : "password";
        toggleSignupPassword.setAttribute(
            "aria-label",
            showPassword ? "Hide password" : "Show password"
        );
    });
}

if (toggleConfirmPassword && confirmPassword) {
    toggleConfirmPassword.addEventListener("click", function () {
        const showPassword = confirmPassword.type === "password";

        confirmPassword.type = showPassword ? "text" : "password";
        toggleConfirmPassword.setAttribute(
            "aria-label",
            showPassword ? "Hide password" : "Show password"
        );
    });
}

if (signupForm) {
    signupForm.addEventListener("submit", function (event) {
        signupError.classList.remove("error-pop");
        void signupError.offsetWidth;

        if (
            signupUsername.value.trim() === "" ||
            signupEmail.value.trim() === "" ||
            signupPassword.value === "" ||
            confirmPassword.value === ""
        ) {
            event.preventDefault();
            signupError.className = "error-message error-pop";
            signupError.textContent = "Please fill in all fields.";
        } else if (signupPassword.value !== confirmPassword.value) {
            event.preventDefault();
            signupError.className = "error-message error-pop";
            signupError.textContent = "Passwords do not match.";
        } else {
            signupError.className = "success-message";
            signupError.textContent = "";
        }
    });
}