// =========================
// STAFF LOGOUT
// =========================
const logoutForm = document.querySelector(".logout-form");

if (logoutForm) {
    const logoutButton = logoutForm.querySelector('button[type="submit"]');

    logoutForm.addEventListener("submit", function () {
        logoutButton.disabled = true;
        logoutButton.textContent = "Logging out...";
    });

    window.addEventListener("pageshow", function (event) {
        // Recheck access if the browser restores a cached page
        if (event.persisted) {
            window.location.reload();
            return;
        }

        logoutButton.disabled = false;
        logoutButton.textContent = "Log out";
    });
}