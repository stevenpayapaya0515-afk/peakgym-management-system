// =========================
// PASSWORD EYE ICONS
// =========================
const eyeIcon = `
    <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.7"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
        focusable="false"
    >
        <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"></path>
        <circle cx="12" cy="12" r="2.5"></circle>
    </svg>
`;

const eyeOffIcon = `
    <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.7"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
        focusable="false"
    >
        <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"></path>
        <circle cx="12" cy="12" r="2.5"></circle>
        <path d="M3 3l18 18"></path>
    </svg>
`;

const passwordToggles = document.querySelectorAll(
    "[data-password-target]"
);

function updateEyeButton(button, input) {
    const visible = input.type === "text";
    const label = document.querySelector(
        `label[for="${input.id}"]`
    ).textContent.trim().toLowerCase();

    button.innerHTML = visible ? eyeOffIcon : eyeIcon;

    button.setAttribute(
        "aria-label",
        `${visible ? "Hide" : "Show"} ${label}`
    );

    button.setAttribute("aria-pressed", String(visible));
}

passwordToggles.forEach(function (button) {
    const input = document.getElementById(
        button.dataset.passwordTarget
    );

    updateEyeButton(button, input);

    button.addEventListener("click", function () {
        input.type = input.type === "password"
            ? "text"
            : "password";

        updateEyeButton(button, input);
    });
});

// =========================
// PASSWORD CONFIRMATION
// =========================
const passwordForm = document.getElementById("passwordForm");
const newPassword = document.getElementById("newPassword");
const confirmPassword = document.getElementById("confirmPassword");
const savePassword = document.getElementById("savePassword");

function validatePasswordMatch() {
    const mismatch =
        confirmPassword.value !== "" &&
        newPassword.value !== confirmPassword.value;

    confirmPassword.setCustomValidity(
        mismatch ? "The new passwords do not match." : ""
    );
}

newPassword.addEventListener("input", validatePasswordMatch);
confirmPassword.addEventListener("input", validatePasswordMatch);

// =========================
// PREVENT REPEATED SUBMISSIONS
// =========================
passwordForm.addEventListener("submit", function (event) {
    validatePasswordMatch();

    if (!passwordForm.reportValidity()) {
        event.preventDefault();
        return;
    }

    savePassword.disabled = true;
    savePassword.textContent = "Saving...";
});

window.addEventListener("pageshow", function () {
    savePassword.disabled = false;
    savePassword.textContent = "Change password";

    passwordToggles.forEach(function (button) {
        const input = document.getElementById(
            button.dataset.passwordTarget
        );

        input.type = "password";
        updateEyeButton(button, input);
    });
});