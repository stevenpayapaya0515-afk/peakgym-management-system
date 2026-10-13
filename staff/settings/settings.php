<?php
session_start();

header("Cache-Control: no-store");
date_default_timezone_set("Asia/Manila");

// =========================
// REQUIRE LOGIN
// =========================
if (empty($_SESSION["user_id"])) {
    header("Location: ../../auth/login.php");
    exit();
}

// =========================
// DATABASE CONNECTION
// =========================
$conn = mysqli_connect(
    "localhost",
    "root",
    "",
    "security_1"
);

if (!$conn) {
    http_response_code(500);
    exit("Unable to connect to the database.");
}

mysqli_set_charset($conn, "utf8mb4");

// =========================
// CHECK CURRENT ACCOUNT
// =========================
$userId = (int) $_SESSION["user_id"];

$stmt = mysqli_prepare(
    $conn,
    "SELECT id, username, email, role, is_active, password
     FROM users
     WHERE id = ?"
);

mysqli_stmt_bind_param($stmt, "i", $userId);
mysqli_stmt_execute($stmt);

$result = mysqli_stmt_get_result($stmt);
$staff = mysqli_fetch_assoc($result);

mysqli_stmt_close($stmt);

if (!$staff || (int) $staff["is_active"] !== 1) {
    $_SESSION = [];
    session_destroy();

    header("Location: ../../auth/login.php");
    exit();
}

if ($staff["role"] !== "staff") {
    http_response_code(403);
    exit("Access denied. This page is for staff accounts.");
}

// =========================
// HELPERS AND FORM STATE
// =========================
function escapeHtml($value) {
    return htmlspecialchars((string) $value, ENT_QUOTES, "UTF-8");
}

function postedString($key) {
    return is_string($_POST[$key] ?? null)
        ? $_POST[$key]
        : "";
}

if (empty($_SESSION["csrf_token"])) {
    $_SESSION["csrf_token"] = bin2hex(random_bytes(32));
}

$error = "";
$success = $_SESSION["settings_success"] ?? "";
unset($_SESSION["settings_success"]);

// =========================
// PROCESS FORM
// =========================
if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $token = postedString("csrf_token");

    if (!hash_equals($_SESSION["csrf_token"], $token)) {
        http_response_code(403);
        exit("Invalid request. Refresh the page and try again.");
    }

    if (postedString("action") !== "change_password") {
        http_response_code(400);
        exit("Invalid action.");
    }

    $currentPassword = postedString("current_password");
    $newPassword = postedString("new_password");
    $confirmPassword = postedString("confirm_password");

    $lockedUntil = (int) (
        $_SESSION["password_change_locked_until"] ?? 0
    );

    // Reset the session's attempt counter after the cooldown.
    if ($lockedUntil > 0 && $lockedUntil <= time()) {
        unset(
            $_SESSION["password_change_attempts"],
            $_SESSION["password_change_locked_until"]
        );

        $lockedUntil = 0;
    }

    if ($lockedUntil > time()) {
        $remaining = $lockedUntil - time();

        $error = "Too many incorrect attempts. Try again in "
            . $remaining . " seconds.";
    } elseif (
        $currentPassword === "" ||
        $newPassword === "" ||
        $confirmPassword === ""
    ) {
        $error = "Please fill in all password fields.";
    } elseif (
        strlen($newPassword) < 12 ||
        strlen($newPassword) > 64
    ) {
        $error = "Use a new password between 12 and 64 bytes.";
    } elseif (
        !preg_match('/[A-Z]/', $newPassword) ||
        !preg_match('/[a-z]/', $newPassword) ||
        !preg_match('/[0-9]/', $newPassword) ||
        !preg_match('/[^a-zA-Z0-9\s]/', $newPassword)
    ) {
        $error = "Include an uppercase letter, lowercase letter, "
            . "number, and symbol.";
    } elseif ($newPassword !== $confirmPassword) {
        $error = "The new passwords do not match.";
    } else {
        $storedPassword = $staff["password"];
        $passwordInfo = password_get_info($storedPassword);
        $isHashed = $passwordInfo["algoName"] !== "unknown";

        // Matches the existing login's legacy password support.
        $currentIsCorrect = $isHashed
            ? password_verify($currentPassword, $storedPassword)
            : hash_equals($storedPassword, $currentPassword);

        if (!$currentIsCorrect) {
            $attempts = (int) (
                $_SESSION["password_change_attempts"] ?? 0
            ) + 1;

            $_SESSION["password_change_attempts"] = $attempts;

            if ($attempts >= 5) {
                $_SESSION["password_change_locked_until"] = time() + 60;

                $error = "Too many incorrect attempts. "
                    . "Try again after 60 seconds.";
            } else {
                $error = "Your current password is incorrect.";
            }
        } elseif ($newPassword === $currentPassword) {
            $error = "Choose a password different from your current password.";
        } else {
            $passwordHash = password_hash(
                $newPassword,
                PASSWORD_DEFAULT
            );

            // Update only the signed-in staff account.
            // The old-password check also prevents overwriting a
            // password that changed during this request.
            $stmt = mysqli_prepare(
                $conn,
                "UPDATE users
                 SET password = ?
                 WHERE id = ?
                   AND role = 'staff'
                   AND is_active = 1
                   AND BINARY password = ?"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "sis",
                $passwordHash,
                $userId,
                $storedPassword
            );

            mysqli_stmt_execute($stmt);
            $updated = mysqli_stmt_affected_rows($stmt);

            mysqli_stmt_close($stmt);

            if ($updated === 1) {
                session_regenerate_id(true);

                $_SESSION["csrf_token"] = bin2hex(random_bytes(32));

                unset(
                    $_SESSION["password_change_attempts"],
                    $_SESSION["password_change_locked_until"]
                );

                $_SESSION["settings_success"] =
                    "Password changed successfully. "
                    . "Use your new password the next time you log in.";

                header("Location: settings.php", true, 303);
                exit();
            }

            $error = "Your account changed while saving. "
                . "Refresh the page and try again.";
        }
    }
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Staff Settings | PeakGym</title>
    <link rel="stylesheet" href="../dashboard_style.css?v=9">
    <link rel="stylesheet" href="settings_style.css?v=5">
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

            <nav class="navigation" aria-label="Staff navigation">
                <a href="../dashboard.php">
                    Dashboard
                </a>

                <a href="../monthly_members/monthly_members.php">
                    Monthly Members
                </a>

                <a
                    href="settings.php"
                    class="active"
                    aria-current="page"
                >
                    Settings
                </a>
            </nav>

            <!-- STAFF PROFILE -->
            <div class="account">
                <div class="account-profile">
                    <div class="account-avatar" aria-hidden="true">
                        <svg
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
                            <?php echo escapeHtml($staff["username"]); ?>
                        </p>

                        <p class="account-role">
                            PeakGym Staff
                        </p>
                    </div>
                </div>

                <form
                    method="POST"
                    action="../dashboard.php"
                    class="logout-form"
                >
                    <input type="hidden" name="action" value="logout">

                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>"
                    >

                    <button type="submit" class="logout">
                        Log out
                    </button>
                </form>
            </div>
        </aside>

        <!-- SETTINGS CONTENT -->
        <main class="main">
            <header class="page-header">
                <h1>Settings</h1>

                <p class="description">
                    View your account details and change your password.
                </p>
            </header>

            <!-- ACCOUNT DETAILS -->
            <section
                class="account-card settings-card"
                aria-labelledby="accountTitle"
            >
                <div class="card-heading">
                    <h2 id="accountTitle">My account</h2>
                    <span class="status">Active</span>
                </div>

                <dl class="account-grid">
                    <div>
                        <dt>Username</dt>
                        <dd>
                            <?php echo escapeHtml($staff["username"]); ?>
                        </dd>
                    </div>

                    <div>
                        <dt>Email</dt>
                        <dd>
                            <?php echo escapeHtml($staff["email"]); ?>
                        </dd>
                    </div>

                    <div>
                        <dt>Role</dt>
                        <dd>Staff</dd>
                    </div>
                </dl>
            </section>

            <!-- CHANGE PASSWORD -->
            <section
                class="account-card settings-card"
                aria-labelledby="passwordTitle"
            >
                <div class="card-heading">
                    <h2 id="passwordTitle">Change password</h2>
                </div>

                <p class="settings-description">
                    Enter your current password to choose a new one.
                </p>

                <?php if ($error !== ""): ?>
                    <div class="settings-message error-message" role="alert">
                        <?php echo escapeHtml($error); ?>
                    </div>
                <?php endif; ?>

                <?php if ($success !== ""): ?>
                    <div class="settings-message success-message" role="status">
                        <?php echo escapeHtml($success); ?>
                    </div>
                <?php endif; ?>

                <form
                    method="POST"
                    action="settings.php"
                    id="passwordForm"
                    class="password-form"
                >
                    <input
                        type="hidden"
                        name="action"
                        value="change_password"
                    >

                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>"
                    >

                    <div class="password-field">
                        <label for="currentPassword">
                            Current password
                        </label>

                        <div class="password-control">
                            <input
                                type="password"
                                id="currentPassword"
                                name="current_password"
                                autocomplete="current-password"
                                required
                            >

                            <button
                                type="button"
                                class="password-toggle"
                                data-password-target="currentPassword"
                                aria-label="Show current password"
                                aria-pressed="false"
                            >
                                Show
                            </button>
                        </div>
                    </div>

                    <div class="password-field">
                        <label for="newPassword">
                            New password
                        </label>

                        <div class="password-control">
                            <input
                                type="password"
                                id="newPassword"
                                name="new_password"
                                autocomplete="new-password"
                                minlength="12"
                                maxlength="64"
                                aria-describedby="passwordHint"
                                required
                            >

                            <button
                                type="button"
                                class="password-toggle"
                                data-password-target="newPassword"
                                aria-label="Show new password"
                                aria-pressed="false"
                            >
                                Show
                            </button>
                        </div>

                        <p id="passwordHint" class="password-hint">
                            Use 12–64 characters with an uppercase letter,
                            lowercase letter, number, and symbol.
                            For letters, numbers, and common symbols,
                            each character is one byte; the server limit
                            is 64 bytes.
                        </p>
                    </div>

                    <div class="password-field">
                        <label for="confirmPassword">
                            Confirm new password
                        </label>

                        <div class="password-control">
                            <input
                                type="password"
                                id="confirmPassword"
                                name="confirm_password"
                                autocomplete="new-password"
                                minlength="12"
                                maxlength="64"
                                required
                            >

                            <button
                                type="button"
                                class="password-toggle"
                                data-password-target="confirmPassword"
                                aria-label="Show confirmed password"
                                aria-pressed="false"
                            >
                                Show
                            </button>
                        </div>
                    </div>

                    <div class="settings-actions">
                        <button
                            type="submit"
                            class="save-password"
                            id="savePassword"
                        >
                            Change password
                        </button>
                    </div>
                </form>
            </section>
        </main>
    </div>

    <script src="../dashboard_script.js?v=1"></script>
    <script src="settings_script.js?v=2"></script>
</body>
</html>