<?php
session_start();

// Prevent the browser from caching this page
header("Cache-Control: no-store");

// =========================
// REQUIRE LOGIN
// =========================
if (empty($_SESSION["user_id"])) {
    header("Location: ../auth/login.php");
    exit();
}

// =========================
// DATABASE CONNECTION
// =========================
$host = "localhost";
$username = "root";
$password = "";
$dbname = "security_1";

$conn = mysqli_connect($host, $username, $password, $dbname);

if (!$conn) {
    die("Database connection failed.");
}

mysqli_set_charset($conn, "utf8mb4");

// =========================
// CHECK ADMINISTRATOR ACCESS
// =========================
$userId = (int) $_SESSION["user_id"];

$stmt = mysqli_prepare(
    $conn,
    "SELECT id, username, role, is_active
     FROM users
     WHERE id = ?"
);

mysqli_stmt_bind_param($stmt, "i", $userId);
mysqli_stmt_execute($stmt);

$result = mysqli_stmt_get_result($stmt);
$admin = mysqli_fetch_assoc($result);

mysqli_stmt_close($stmt);

if (
    !$admin ||
    $admin["role"] !== "admin" ||
    (int) $admin["is_active"] !== 1
) {
    $_SESSION = [];
    session_destroy();

    header("Location: ../auth/login.php");
    exit();
}

// Protect form submissions
if (empty($_SESSION["csrf_token"])) {
    $_SESSION["csrf_token"] = bin2hex(random_bytes(32));
}

// Safely display values in HTML
function escapeHtml($value) {
    return htmlspecialchars((string) $value, ENT_QUOTES, "UTF-8");
}

// =========================
// FORM VALUES AND MESSAGES
// =========================
$createError = "";
$staffUsername = "";
$staffEmail = "";

$createSuccess = $_SESSION["staff_success"] ?? "";
unset($_SESSION["staff_success"]);

// =========================
// PROCESS FORM SUBMISSIONS
// =========================
if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $token = $_POST["csrf_token"] ?? "";

    if (
        !is_string($token) ||
        !hash_equals($_SESSION["csrf_token"], $token)
    ) {
        http_response_code(403);
        exit("Invalid request. Refresh the page and try again.");
    }

    $action = $_POST["action"] ?? "";

    // =========================
    // UPDATE STAFF STATUS
    // =========================
    if ($action === "update_status") {
        $staffId = filter_var(
            $_POST["staff_id"] ?? "",
            FILTER_VALIDATE_INT
        );

        $newStatus = $_POST["is_active"] ?? "";

        if (
            $staffId === false ||
            $staffId < 1 ||
            !in_array($newStatus, ["0", "1"], true)
        ) {
            http_response_code(400);
            exit("Invalid staff account or status.");
        }

        // Confirm the selected account is staff
        $check = mysqli_prepare(
            $conn,
            "SELECT id
             FROM users
             WHERE id = ? AND role = 'staff'"
        );

        mysqli_stmt_bind_param($check, "i", $staffId);
        mysqli_stmt_execute($check);

        $staffResult = mysqli_stmt_get_result($check);
        $staffExists = mysqli_fetch_assoc($staffResult);

        mysqli_stmt_close($check);

        if (!$staffExists) {
            http_response_code(404);
            exit("Staff account not found.");
        }

        $statusValue = (int) $newStatus;

        $update = mysqli_prepare(
            $conn,
            "UPDATE users
             SET is_active = ?
             WHERE id = ? AND role = 'staff'"
        );

        mysqli_stmt_bind_param(
            $update,
            "ii",
            $statusValue,
            $staffId
        );

        mysqli_stmt_execute($update);
        mysqli_stmt_close($update);

        $_SESSION["staff_success"] = $statusValue === 1
            ? "Staff account activated successfully."
            : "Staff account deactivated successfully.";

        header("Location: user_management.php", true, 303);
        exit();
    }

    // =========================
    // DELETE STAFF ACCOUNT
    // =========================
    if ($action === "delete_staff") {
        $staffId = filter_var(
            $_POST["staff_id"] ?? "",
            FILTER_VALIDATE_INT
        );

        if ($staffId === false || $staffId < 1) {
            http_response_code(400);
            exit("Invalid staff account.");
        }

        // Administrator accounts cannot be deleted here
        $delete = mysqli_prepare(
            $conn,
            "DELETE FROM users
             WHERE id = ? AND role = 'staff'"
        );

        mysqli_stmt_bind_param($delete, "i", $staffId);
        mysqli_stmt_execute($delete);

        $deleted = mysqli_stmt_affected_rows($delete);
        mysqli_stmt_close($delete);

        if ($deleted !== 1) {
            http_response_code(404);
            exit("Staff account not found.");
        }

        $_SESSION["staff_success"] =
            "Staff account deleted successfully.";

        header("Location: user_management.php", true, 303);
        exit();
    }

    // =========================
    // CREATE STAFF ACCOUNT
    // =========================
    if ($action !== "create_staff") {
        http_response_code(400);
        exit("Invalid action.");
    }

    $staffUsername = is_string($_POST["staff_username"] ?? null)
        ? trim($_POST["staff_username"]) : "";

    $staffEmail = is_string($_POST["staff_email"] ?? null)
        ? strtolower(trim($_POST["staff_email"])) : "";

    // Do not trim passwords
    $staffPassword = is_string($_POST["staff_password"] ?? null)
        ? $_POST["staff_password"] : "";

    $confirmPassword = is_string($_POST["confirm_password"] ?? null)
        ? $_POST["confirm_password"] : "";

    // Validate account details
    if (
        $staffUsername === "" ||
        $staffEmail === "" ||
        $staffPassword === "" ||
        $confirmPassword === ""
    ) {
        $createError = "Please fill in all fields.";
    } elseif (
        !preg_match('/^[a-zA-Z0-9_.-]{3,50}$/', $staffUsername)
    ) {
        $createError =
            "Username must be 3–50 characters using letters, numbers, dots, underscores, or hyphens.";
    } elseif (
        strlen($staffEmail) > 100 ||
        !filter_var($staffEmail, FILTER_VALIDATE_EMAIL)
    ) {
        $createError = "Please enter a valid email address.";
    } elseif (
        strlen($staffPassword) < 12 ||
        strlen($staffPassword) > 72
    ) {
        $createError =
            "Password must be 12–72 bytes (12–72 characters for plain English text).";
    } elseif (strpos($staffPassword, "\0") !== false) {
        $createError = "Password contains an invalid character.";
    } elseif ($staffPassword !== $confirmPassword) {
        $createError = "Passwords do not match.";
    } else {
        // Check for existing usernames or emails
        $check = mysqli_prepare(
            $conn,
            "SELECT id
             FROM users
             WHERE username = ? OR email = ?
                OR username = ? OR email = ?
             LIMIT 1"
        );

        mysqli_stmt_bind_param(
            $check,
            "ssss",
            $staffUsername,
            $staffEmail,
            $staffEmail,
            $staffUsername
        );

        mysqli_stmt_execute($check);
        $existing = mysqli_stmt_get_result($check);

        if (mysqli_num_rows($existing) > 0) {
            $createError = "That username or email is already in use.";
        }

        mysqli_stmt_close($check);

        if ($createError === "") {
            // Store a hash instead of the plain password
            $passwordHash = password_hash(
                $staffPassword,
                PASSWORD_DEFAULT
            );

            try {
                $insert = mysqli_prepare(
                    $conn,
                    "INSERT INTO users
                        (username, email, password, role, is_active,
                         failed_attempts, locked_until)
                     VALUES (?, ?, ?, 'staff', 1, 0, NULL)"
                );

                mysqli_stmt_bind_param(
                    $insert,
                    "sss",
                    $staffUsername,
                    $staffEmail,
                    $passwordHash
                );

                $saved = mysqli_stmt_execute($insert);
                mysqli_stmt_close($insert);

                if ($saved) {
                    $_SESSION["staff_success"] =
                        "Staff account created successfully.";

                    // Prevent duplicate submission on refresh
                    header("Location: user_management.php", true, 303);
                    exit();
                }

                $createError =
                    "Unable to create the account. Please try again.";
            } catch (mysqli_sql_exception $error) {
                if ((int) $error->getCode() === 1062) {
                    $createError =
                        "That username or email is already in use.";
                } else {
                    $createError =
                        "Unable to create the account. Please try again.";
                }
            }
        }
    }
}

// =========================
// GET STAFF ACCOUNTS
// =========================
$sql = "SELECT id, username, email, is_active
        FROM users
        WHERE role = 'staff'
        ORDER BY id DESC";

$result = mysqli_query($conn, $sql);
$staffAccounts = mysqli_fetch_all($result, MYSQLI_ASSOC);
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Staff Management | PeakGym</title>
    <link rel="stylesheet" href="user_management_style.css?v=14">
    <link rel="icon" type="image/png" href="/Payapaya_Security1/assets/favicon.png">
</head>

<body>
    <div class="layout">

        <!-- SIDEBAR -->
        <aside class="sidebar">
            <div class="sidebar-brand">
                <img
                    src="/Payapaya_Security1/assets/logo_peak.png"
                    alt="Peak Gym logo"
                    class="sidebar-brand-image"
                >

                <div class="sidebar-brand-text">
                    <div class="logo">PEAKGYM</div>
                    <p class="sidebar-caption">Management System</p>
                </div>
            </div>

            <nav class="navigation" aria-label="Admin navigation">
                <a href="../dashboard.php">Dashboard</a>

                <a
                    href="user_management.php"
                    class="active"
                    aria-current="page"
                >
                    Staff Management
                </a>

                <a href="../../staff/monthly_members/monthly_members.php">
                    Monthly Members
                </a>
            </nav>

            <!-- ADMIN PROFILE AND LOGOUT -->
            <div class="account">
                <div class="account-profile">
                    <div class="account-avatar" aria-hidden="true">
                        <svg
                            xmlns="http://www.w3.org/2000/svg"
                            width="16"
                            height="16"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="1.7"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                        >
                            <circle cx="12" cy="8" r="4"></circle>
                            <path d="M4 21v-2a8 8 0 0 1 16 0v2"></path>
                        </svg>
                    </div>

                    <div class="account-details">
                        <p class="account-name">
                            <?php echo escapeHtml($admin["username"]); ?>
                        </p>

                        <p class="account-role">PeakGym Administrator</p>
                    </div>
                </div>

                <form method="POST" action="../dashboard.php" class="logout-form">
                    <input type="hidden" name="action" value="logout">

                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>"
                    >

                    <button type="submit" class="logout">Log out</button>
                </form>
            </div>
        </aside>

        <!-- MAIN CONTENT -->
        <main class="main">
            <header class="page-header">
                <h1>Staff Management</h1>

                <p class="description">
                    Create staff accounts and manage their access.
                </p>
            </header>

            <!-- SEARCH AND CREATE BUTTON -->
            <div class="staff-toolbar">
                <div class="staff-search">
                    <svg viewBox="0 0 24 24" aria-hidden="true">
                        <circle cx="10.5" cy="10.5" r="6.5"></circle>
                        <path d="m16 16 4.5 4.5"></path>
                    </svg>

                    <input
                        type="search"
                        id="staffSearch"
                        placeholder="Search username or email..."
                        aria-label="Search staff by username or email"
                        autocomplete="off"
                    >
                </div>

                <button
                    type="button"
                    class="create-staff-button"
                    id="openStaffForm"
                    aria-controls="staffCreatePanel"
                    aria-expanded="true"
                >
                    Create staff account
                </button>
            </div>

            <!-- CREATE STAFF FORM -->
            <section
                class="staff-create-panel"
                id="staffCreatePanel"
                aria-labelledby="staffCreateTitle"
                data-has-error="<?php echo $createError !== "" ? "1" : "0"; ?>"
            >
                <h2 id="staffCreateTitle">Create staff account</h2>

                <p class="staff-form-description">
                    Enter the staff member’s account details.
                </p>

                <form
                    method="POST"
                    action="user_management.php"
                    id="createStaffForm"
                >
                    <input type="hidden" name="action" value="create_staff">

                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>"
                    >

                    <div class="staff-form-grid">
                        <div class="staff-field">
                            <label for="staffUsername">Username</label>

                            <input
                                type="text"
                                id="staffUsername"
                                name="staff_username"
                                value="<?php echo escapeHtml($staffUsername); ?>"
                                placeholder="juan.delacruz"
                                minlength="3"
                                maxlength="50"
                                pattern="[a-zA-Z0-9_.\-]{3,50}"
                                title="Use 3–50 letters, numbers, dots, underscores, or hyphens."
                                autocomplete="off"
                                required
                            >
                        </div>

                        <div class="staff-field">
                            <label for="staffEmail">Email</label>

                            <input
                                type="email"
                                id="staffEmail"
                                name="staff_email"
                                value="<?php echo escapeHtml($staffEmail); ?>"
                                placeholder="juan.delacruz@peakgym.com"
                                maxlength="100"
                                autocomplete="off"
                                required
                            >
                        </div>

                        <div class="staff-field">
                            <label for="staffPassword">Password</label>

                            <input
                                type="password"
                                id="staffPassword"
                                name="staff_password"
                                minlength="12"
                                maxlength="72"
                                autocomplete="new-password"
                                aria-describedby="staffPasswordHint"
                                required
                            >
                        </div>

                        <div class="staff-field">
                            <label for="staffConfirmPassword">
                                Confirm password
                            </label>

                            <input
                                type="password"
                                id="staffConfirmPassword"
                                name="confirm_password"
                                minlength="12"
                                maxlength="72"
                                autocomplete="new-password"
                                required
                            >
                        </div>
                    </div>

                    <p class="staff-password-hint" id="staffPasswordHint">
                        Use a long, unique password with at least 12 characters.
                    </p>

                    <label class="staff-show-password">
                        <input type="checkbox" id="showStaffPasswords">
                        Show passwords
                    </label>

                    <p class="staff-form-error" id="staffFormError" role="alert"><?php echo escapeHtml($createError); ?></p>

                    <div class="staff-form-actions">
                        <button
                            type="button"
                            class="staff-cancel"
                            id="cancelStaffForm"
                        >
                            Cancel
                        </button>

                        <button
                            type="submit"
                            class="create-staff-button"
                            id="saveStaffButton"
                        >
                            Create account
                        </button>
                    </div>
                </form>
            </section>

            <!-- STAFF LIST -->
            <div class="table-container overview-card">
                <table aria-label="Staff accounts">
                    <thead>
                        <tr>
                            <th scope="col">Username</th>
                            <th scope="col">Email</th>
                            <th scope="col">Status</th>
                            <th scope="col">Actions</th>
                        </tr>
                    </thead>

                    <tbody>
                        <?php if (empty($staffAccounts)): ?>
                            <tr>
                                <td colspan="4" class="empty">
                                    No staff accounts yet.
                                </td>
                            </tr>
                        <?php else: ?>
                            <?php foreach ($staffAccounts as $staff): ?>
                                <tr>
                                    <td>
                                        <?php echo escapeHtml($staff["username"]); ?>
                                    </td>

                                    <td>
                                        <?php echo escapeHtml($staff["email"]); ?>
                                    </td>

                                    <td>
                                        <?php if ((int) $staff["is_active"] === 1): ?>
                                            <span class="status green">Active</span>
                                        <?php else: ?>
                                            <span class="status yellow">Inactive</span>
                                        <?php endif; ?>
                                    </td>

                                    <td>
                                        <div class="staff-actions">
                                            <button
                                                type="button"
                                                class="staff-edit-button"
                                                data-id="<?php echo (int) $staff["id"]; ?>"
                                                data-username="<?php echo escapeHtml($staff["username"]); ?>"
                                                data-status="<?php echo (int) $staff["is_active"]; ?>"
                                            >
                                                Edit
                                            </button>

                                            <button
                                                type="button"
                                                class="staff-delete-button"
                                                data-id="<?php echo (int) $staff["id"]; ?>"
                                                data-username="<?php echo escapeHtml($staff["username"]); ?>"
                                            >
                                                Delete
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </main>
    </div>

    <!-- SUCCESS POPUP -->
    <?php if ($createSuccess !== ""): ?>
        <dialog
            class="staff-success-modal"
            id="staffSuccessModal"
            aria-labelledby="successTitle"
            aria-describedby="successMessage"
        >
            <div class="success-icon" aria-hidden="true">✓</div>

            <h2 id="successTitle">Successful!</h2>

            <p id="successMessage">
                <?php echo escapeHtml($createSuccess); ?>
            </p>

            <form method="dialog">
                <button type="submit" class="create-staff-button" autofocus>
                    Okay
                </button>
            </form>
        </dialog>

        <noscript>
            <p class="staff-success">
                <?php echo escapeHtml($createSuccess); ?>
            </p>
        </noscript>
    <?php endif; ?>

    <!-- EDIT STAFF STATUS MODAL -->
    <dialog
        id="editStaffModal"
        class="staff-action-modal"
        aria-labelledby="editStaffTitle"
    >
        <h2 id="editStaffTitle">Edit staff status</h2>

        <p class="staff-modal-description" id="editStaffName"></p>

        <form
            method="POST"
            action="user_management.php"
            id="editStaffStatusForm"
        >
            <input type="hidden" name="action" value="update_status">

            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>"
            >

            <input type="hidden" name="staff_id" id="editStaffId">

            <label for="editStaffStatus">Status</label>

            <select name="is_active" id="editStaffStatus">
                <option value="1">Active</option>
                <option value="0">Inactive</option>
            </select>

            <div class="staff-modal-buttons">
                <button
                    type="button"
                    class="staff-cancel"
                    id="cancelStaffEdit"
                >
                    Cancel
                </button>

                <button type="submit" class="create-staff-button">
                    Save
                </button>
            </div>
        </form>
    </dialog>

    <!-- DELETE STAFF CONFIRMATION -->
    <dialog
        id="deleteStaffModal"
        class="staff-action-modal"
        aria-labelledby="deleteStaffTitle"
    >
        <h2 id="deleteStaffTitle">Delete staff account?</h2>

        <p class="staff-modal-description">
            Permanently delete <strong id="deleteStaffName"></strong>?
            This cannot be undone.
        </p>

        <form
            method="POST"
            action="user_management.php"
            id="deleteStaffForm"
        >
            <input type="hidden" name="action" value="delete_staff">

            <input
                type="hidden"
                name="csrf_token"
                value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>"
            >

            <input type="hidden" name="staff_id" id="deleteStaffId">

            <div class="staff-modal-buttons">
                <button
                    type="button"
                    class="staff-cancel"
                    id="cancelStaffDelete"
                >
                    Cancel
                </button>

                <button type="submit" class="staff-confirm-delete">
                    Delete
                </button>
            </div>
        </form>
    </dialog>

    <script src="user_management_script.js?v=5"></script>
</body>
</html>