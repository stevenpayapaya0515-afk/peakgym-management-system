// =========================
// DASHBOARD LOGOUT
// =========================
const logoutForm = document.querySelector(".logout-form");

if (logoutForm) {
    const logoutButton = logoutForm.querySelector('button[type="submit"]');

    // Prevent repeated clicks while logging out
    logoutForm.addEventListener("submit", function () {
        logoutButton.disabled = true;
        logoutButton.textContent = "Logging out...";
    });

    // Reset the button when the browser restores the page
    window.addEventListener("pageshow", function () {
        logoutButton.disabled = false;
        logoutButton.textContent = "Log out";
    });
}