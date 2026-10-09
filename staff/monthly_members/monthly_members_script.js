// =========================
// FORM ELEMENTS
// =========================
const memberPanel = document.getElementById("memberPanel");
const memberForm = document.getElementById("memberForm");
const memberAction = document.getElementById("memberAction");
const memberId = document.getElementById("memberId");
const membershipId = document.getElementById("membershipId");
const memberName = document.getElementById("memberName");
const startDate = document.getElementById("startDate");
const dueDate = document.getElementById("dueDate");
const saveMember = document.getElementById("saveMember");

const panelTitle = document.getElementById("memberPanelTitle");

const panelDescription = document.getElementById(
    "memberPanelDescription"
);

const editorGrid = document.querySelector(
    ".member-editor-grid"
);

const dateHint = document.getElementById("dateHint");

// =========================
// PHOTO ELEMENTS
// =========================
const photoFields = document.getElementById("photoFields");
const memberPhoto = document.getElementById("memberPhoto");
const photoPreview = document.getElementById("photoPreview");

const photoPlaceholder = document.getElementById(
    "photoPlaceholder"
);

const photoFileName = document.getElementById("photoFileName");
const photoHint = document.getElementById("photoHint");
const photoError = document.getElementById("photoError");

let existingPhoto = "";
let previewUrl = null;
let lastTrigger = null;

// =========================
// TODAY IN THE PHILIPPINES
// =========================
const dateParts = new Intl.DateTimeFormat("en", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
}).formatToParts(new Date());

const parts = Object.fromEntries(
    dateParts.map(function (part) {
        return [part.type, part.value];
    })
);

const today = `${parts.year}-${parts.month}-${parts.day}`;

// =========================
// CALCULATE DUE DATE
// =========================
function calculateDueDate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        return "";
    }

    const [year, month, day] = value.split("-").map(Number);

    if (
        year < 1900 ||
        year > 2099 ||
        month < 1 ||
        month > 12 ||
        day < 1
    ) {
        return "";
    }

    const check = new Date(
        Date.UTC(year, month - 1, day)
    );

    if (check.getUTCMonth() !== month - 1) {
        return "";
    }

    const nextMonth = new Date(
        Date.UTC(year, month, 1)
    );

    const lastDay = new Date(
        Date.UTC(year, month + 1, 0)
    ).getUTCDate();

    nextMonth.setUTCDate(Math.min(day, lastDay));

    return nextMonth.toISOString().slice(0, 10);
}

startDate.addEventListener("input", function () {
    dueDate.min = startDate.value || "1900-01-01";
    dueDate.value = calculateDueDate(startDate.value);
});

// =========================
// PHOTO PREVIEW
// =========================
function releasePreview() {
    if (previewUrl) {
        URL.revokeObjectURL(previewUrl);
        previewUrl = null;
    }
}

function showPhoto(url) {
    photoPreview.hidden = !url;
    photoPlaceholder.hidden = Boolean(url);
    photoPlaceholder.textContent = "No photo";

    if (url) {
        photoPreview.src = url;
    } else {
        photoPreview.removeAttribute("src");
    }
}

photoPreview.addEventListener("error", function () {
    photoPreview.hidden = true;
    photoPlaceholder.hidden = false;
    photoPlaceholder.textContent = "Photo unavailable";
});

memberPhoto.addEventListener("change", function () {
    releasePreview();
    photoError.hidden = true;

    const file = memberPhoto.files[0];

    if (!file) {
        showPhoto(existingPhoto);

        photoFileName.textContent = existingPhoto
            ? "Current photo"
            : "No file selected";

        return;
    }

    const validName = /\.(png|jpe?g)$/i.test(file.name);

    const validSize =
        file.size > 0 &&
        file.size <= 2 * 1024 * 1024;

    if (!validName || !validSize) {
        memberPhoto.value = "";
        showPhoto(existingPhoto);

        photoFileName.textContent = existingPhoto
            ? "Current photo"
            : "No file selected";

        photoError.textContent =
            "Choose a PNG or JPEG photo, maximum 2 MB.";

        photoError.hidden = false;
        return;
    }

    // The PHP backend also validates the actual image contents.
    previewUrl = URL.createObjectURL(file);

    showPhoto(previewUrl);
    photoFileName.textContent = file.name;
});

// =========================
// SAVE BUTTON LABEL
// =========================
function resetSaveButton() {
    saveMember.disabled = false;

    if (memberAction.value === "edit") {
        saveMember.textContent = "Save changes";
    } else if (memberAction.value === "renew") {
        saveMember.textContent = "Renew membership";
    } else {
        saveMember.textContent = "Save member";
    }
}

// =========================
// OPEN FORM PANEL
// =========================
function openMemberPanel(action, data, trigger) {
    memberForm.reset();
    releasePreview();

    lastTrigger = trigger;

    const editing = action === "edit";
    const renewing = action === "renew";

    memberAction.value = action;
    memberId.value = data.id || "";
    membershipId.value = data.period || "";

    memberName.value = data.name || "";
    memberName.readOnly = renewing;

    // Start and due date remain visible in Edit.
    startDate.disabled = false;
    startDate.required = true;
    startDate.value = data.start || today;

    dueDate.disabled = false;
    dueDate.required = true;
    dueDate.readOnly = !editing;
    dueDate.min = startDate.value;

    // Preserve the stored due date when Edit first opens.
    dueDate.value = editing
        ? data.due || calculateDueDate(startDate.value)
        : calculateDueDate(startDate.value);

    photoFields.hidden = renewing;
    memberPhoto.disabled = renewing;
    photoError.hidden = true;

    existingPhoto = data.photo || "";

    showPhoto(existingPhoto);

    photoFileName.textContent = existingPhoto
        ? "Current photo"
        : "No file selected";

    photoHint.textContent = editing
        ? "PNG or JPEG · Up to 2 MB. Leave unchanged to keep the current photo."
        : "Optional · PNG or JPEG · Up to 2 MB";

    editorGrid.classList.toggle(
        "renew-layout",
        renewing
    );

    if (editing) {
        panelTitle.textContent = "Edit member";

        panelDescription.textContent =
            "Update the member’s photo, name, and membership dates.";

        dateHint.textContent =
            "You can correct both dates. The due date is the last valid workout day.";
    } else if (renewing) {
        panelTitle.textContent = "Renew membership";

        panelDescription.textContent =
            "Add a new membership period for this member.";

        dateHint.textContent =
            "Due date is calculated one calendar month after the start date.";
    } else {
        panelTitle.textContent = "Add member";

        panelDescription.textContent =
            "Enter the member’s information and monthly start date.";

        dateHint.textContent =
            "Due date is calculated automatically and is the last valid workout day.";
    }

    resetSaveButton();

    memberPanel.hidden = false;

    memberPanel.scrollIntoView({
        behavior: "auto",
        block: "nearest"
    });

    const firstField = renewing ? startDate : memberName;

    firstField.focus({
        preventScroll: true
    });
}

// =========================
// CLOSE FORM PANEL
// =========================
function closeMemberPanel() {
    memberPanel.hidden = true;
    releasePreview();

    if (lastTrigger) {
        lastTrigger.focus({
            preventScroll: true
        });
    }
}

document.getElementById("closeMemberPanel").addEventListener(
    "click",
    closeMemberPanel
);

document.getElementById("cancelMember").addEventListener(
    "click",
    closeMemberPanel
);

// =========================
// ADD MEMBER
// =========================
document.getElementById("addMember").addEventListener(
    "click",
    function () {
        openMemberPanel("add", {}, this);
    }
);

// =========================
// EDIT MEMBER
// =========================
document.querySelectorAll(".edit-member").forEach(
    function (button) {
        button.addEventListener("click", function () {
            openMemberPanel(
                "edit",
                button.dataset,
                button
            );
        });
    }
);

// =========================
// RENEW MEMBERSHIP
// =========================
document.querySelectorAll(".renew-member").forEach(
    function (button) {
        button.addEventListener("click", function () {
            openMemberPanel(
                "renew",
                button.dataset,
                button
            );
        });
    }
);

// =========================
// SUBMIT FORM
// =========================
memberForm.addEventListener("submit", function (event) {
    if (memberName.value.trim() === "") {
        event.preventDefault();
        memberName.focus();
        return;
    }

    if (!memberForm.checkValidity()) {
        event.preventDefault();
        memberForm.reportValidity();
        return;
    }

    saveMember.disabled = true;
    saveMember.textContent = "Saving...";
});

window.addEventListener("pageshow", resetSaveButton);

// =========================
// MEMBERSHIP HISTORY
// =========================
document.querySelectorAll(".history-button").forEach(
    function (button) {
        button.addEventListener("click", function () {
            const historyDialog = document.getElementById(
                button.dataset.target
            );

            if (historyDialog) {
                historyDialog.showModal();
            }
        });
    }
);

// =========================
// CLOSE HISTORY DIALOGS
// =========================
document.querySelectorAll("[data-close]").forEach(
    function (button) {
        button.addEventListener("click", function () {
            const dialog = button.closest("dialog");

            if (dialog) {
                dialog.close();
            }
        });
    }
);

// =========================
// SUCCESS MESSAGE
// =========================
const memberSuccess = document.getElementById(
    "memberSuccess"
);

if (memberSuccess) {
    memberSuccess.showModal();
}

// =========================
// SEARCH MEMBERS
// =========================
const memberSearch = document.getElementById("memberSearch");
const memberRows = document.querySelectorAll(".member-row");
const emptyMembers = document.getElementById("emptyMembers");

function filterMembers() {
    const query = memberSearch.value.trim().toLowerCase();

    let matches = 0;

    memberRows.forEach(function (row) {
        const visible = row.dataset.name
            .toLowerCase()
            .includes(query);

        row.hidden = !visible;

        if (visible) {
            matches++;
        }
    });

    emptyMembers.hidden = matches > 0;
}

memberSearch.addEventListener("input", filterMembers);
window.addEventListener("pageshow", filterMembers);


// =========================
// DELETE MEMBER
// =========================
const deleteMemberModal = document.getElementById(
    "deleteMemberModal"
);

const deleteMemberForm = document.getElementById(
    "deleteMemberForm"
);

const deleteMemberId = document.getElementById(
    "deleteMemberId"
);

const deleteMemberName = document.getElementById(
    "deleteMemberName"
);

const confirmDeleteMember = document.getElementById(
    "confirmDeleteMember"
);

document.querySelectorAll(".delete-member").forEach(
    function (button) {
        button.addEventListener("click", function () {
            deleteMemberId.value = button.dataset.id;
            deleteMemberName.textContent = button.dataset.name;

            confirmDeleteMember.disabled = false;
            confirmDeleteMember.textContent = "Delete member";

            deleteMemberModal.showModal();
        });
    }
);

deleteMemberForm.addEventListener("submit", function () {
    confirmDeleteMember.disabled = true;
    confirmDeleteMember.textContent = "Deleting...";
});

window.addEventListener("pageshow", function () {
    confirmDeleteMember.disabled = false;
    confirmDeleteMember.textContent = "Delete member";
});