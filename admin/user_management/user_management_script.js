// =========================
// LOGOUT
// =========================
const logoutForm = document.querySelector(".logout-form");

if (logoutForm) {
    const logoutButton = logoutForm.querySelector('button[type="submit"]');

    logoutForm.addEventListener("submit", function () {
        logoutButton.disabled = true;
        logoutButton.textContent = "Logging out...";
    });

    window.addEventListener("pageshow", function () {
        logoutButton.disabled = false;
        logoutButton.textContent = "Log out";
    });
}

// =========================
// STAFF FORM ELEMENTS
// =========================
const staffPanel = document.getElementById("staffCreatePanel");
const openStaffForm = document.getElementById("openStaffForm");
const cancelStaffForm = document.getElementById("cancelStaffForm");
const createStaffForm = document.getElementById("createStaffForm");
const staffUsername = document.getElementById("staffUsername");
const staffPassword = document.getElementById("staffPassword");
const staffConfirmPassword = document.getElementById("staffConfirmPassword");
const showStaffPasswords = document.getElementById("showStaffPasswords");
const staffFormError = document.getElementById("staffFormError");
const saveStaffButton = document.getElementById("saveStaffButton");

if (createStaffForm) {
    // Keep the form open if PHP returned an error
    staffPanel.hidden = staffPanel.dataset.hasError !== "1";
    openStaffForm.setAttribute(
        "aria-expanded",
        String(!staffPanel.hidden)
    );
    // Hide the opening button while the form is visible
    openStaffForm.hidden = !staffPanel.hidden;

    // Open the form and hide the opening button
    openStaffForm.addEventListener("click", function () {
        staffPanel.hidden = false;
        openStaffForm.hidden = true;
        openStaffForm.setAttribute("aria-expanded", "true");
        staffUsername.focus();
    });

    // Close the form and clear passwords
    cancelStaffForm.addEventListener("click", function () {
        createStaffForm.reset();

        staffPassword.value = "";
        staffConfirmPassword.value = "";
        staffPassword.type = "password";
        staffConfirmPassword.type = "password";
        showStaffPasswords.checked = false;
        staffFormError.textContent = "";

        staffPanel.hidden = true;
        openStaffForm.setAttribute("aria-expanded", "false");
        
        // Show the opening button again
        openStaffForm.hidden = false;
        openStaffForm.focus();
    });

    // Show or hide both password fields
    showStaffPasswords.addEventListener("change", function () {
        const inputType = this.checked ? "text" : "password";

        staffPassword.type = inputType;
        staffConfirmPassword.type = inputType;
    });

    // Validate before sending the form to PHP
    createStaffForm.addEventListener("submit", function (event) {
        staffFormError.textContent = "";

        // Check the same byte limit used by PHP
        const passwordBytes = new TextEncoder()
            .encode(staffPassword.value).length;

        if (passwordBytes < 12 || passwordBytes > 72) {
            event.preventDefault();
            staffFormError.textContent =
                "Password must be 12–72 bytes (12–72 characters for plain English text).";
            staffPassword.focus();
            return;
        }

        if (staffPassword.value !== staffConfirmPassword.value) {
            event.preventDefault();
            staffFormError.textContent = "Passwords do not match.";
            staffConfirmPassword.focus();
            return;
        }

        // Allow the normal PHP form submission
        saveStaffButton.disabled = true;
        saveStaffButton.textContent = "Creating...";
    });

    window.addEventListener("pageshow", function () {
        saveStaffButton.disabled = false;
        saveStaffButton.textContent = "Create account";
    });
}

// =========================
// SHOW SUCCESS POPUP
// =========================
const staffSuccessModal = document.getElementById("staffSuccessModal");

if (staffSuccessModal) {
    staffSuccessModal.showModal();
}

// =========================
// EDIT STAFF STATUS MODAL
// =========================
const editStaffModal = document.getElementById("editStaffModal");
const editStaffId = document.getElementById("editStaffId");
const editStaffName = document.getElementById("editStaffName");
const editStaffStatus = document.getElementById("editStaffStatus");
const editStaffStatusForm = document.getElementById("editStaffStatusForm");

document.querySelectorAll(".staff-edit-button").forEach(function (button) {
    button.addEventListener("click", function () {
        editStaffId.value = button.dataset.id;
        editStaffName.textContent = button.dataset.username;
        editStaffStatus.value = button.dataset.status;

        editStaffModal.showModal();
        editStaffStatus.focus();
    });
});

document.getElementById("cancelStaffEdit").addEventListener("click", function () {
    editStaffModal.close();
});

// =========================
// DELETE STAFF MODAL
// =========================
const deleteStaffModal = document.getElementById("deleteStaffModal");
const deleteStaffId = document.getElementById("deleteStaffId");
const deleteStaffName = document.getElementById("deleteStaffName");
const deleteStaffForm = document.getElementById("deleteStaffForm");
const cancelStaffDelete = document.getElementById("cancelStaffDelete");

document.querySelectorAll(".staff-delete-button").forEach(function (button) {
    button.addEventListener("click", function () {
        deleteStaffId.value = button.dataset.id;
        deleteStaffName.textContent = button.dataset.username;

        deleteStaffModal.showModal();
        cancelStaffDelete.focus();
    });
});

cancelStaffDelete.addEventListener("click", function () {
    deleteStaffModal.close();
});

// Prevent repeated submissions
editStaffStatusForm.addEventListener("submit", function () {
    const button = this.querySelector('button[type="submit"]');
    button.disabled = true;
    button.textContent = "Saving...";
});

deleteStaffForm.addEventListener("submit", function () {
    const button = this.querySelector('button[type="submit"]');
    button.disabled = true;
    button.textContent = "Deleting...";
});

// Restore buttons after browser back navigation
window.addEventListener("pageshow", function () {
    const saveButton = editStaffStatusForm.querySelector('button[type="submit"]');
    saveButton.disabled = false;
    saveButton.textContent = "Save";

    const deleteButton = deleteStaffForm.querySelector('button[type="submit"]');
    deleteButton.disabled = false;
    deleteButton.textContent = "Delete";
});


// =========================
// SEARCH STAFF ACCOUNTS
// =========================
const staffSearch = document.getElementById("staffSearch");
const staffTableBody = document.querySelector(".table-container tbody");

if (staffSearch && staffTableBody) {
    // Get actual staff rows, excluding the empty-table message
    const staffRows = Array.from(staffTableBody.rows).filter(function (row) {
        return row.querySelector(".staff-actions") !== null;
    });

    // Add a message for searches with no matches
    const noResultsRow = document.createElement("tr");
    const noResultsCell = document.createElement("td");

    noResultsCell.colSpan = 4;
    noResultsCell.className = "empty";
    noResultsCell.textContent = "No matching staff accounts.";

    noResultsRow.appendChild(noResultsCell);
    noResultsRow.hidden = true;
    staffTableBody.appendChild(noResultsRow);

    function filterStaff() {
        const searchText = staffSearch.value.trim().toLowerCase();
        let matchCount = 0;

        staffRows.forEach(function (row) {
            const username = row.cells[0].textContent.toLowerCase();
            const email = row.cells[1].textContent.toLowerCase();

            const matches =
                username.includes(searchText) ||
                email.includes(searchText);

            row.hidden = !matches;

            if (matches) {
                matchCount++;
            }
        });

        // Keep "No staff accounts yet" when the table is empty
        noResultsRow.hidden =
            staffRows.length === 0 || matchCount > 0;
    }

    staffSearch.addEventListener("input", filterStaff);
    window.addEventListener("pageshow", filterStaff);

    filterStaff();
}