<?php
session_start();

header("Cache-Control: no-store");
date_default_timezone_set("Asia/Manila");

// =========================
// DATABASE CONNECTION
// =========================
$host = "localhost";
$username = "root";
$password = "";
$dbname = "security_1";

$conn = mysqli_connect($host, $username, $password, $dbname);

if (!$conn) {
    http_response_code(500);
    exit("Unable to connect to the database.");
}

mysqli_set_charset($conn, "utf8mb4");

// =========================
// REDIRECT LOGGED-IN USERS
// =========================
if (!empty($_SESSION["user_id"])) {
    $sessionUserId = (int) $_SESSION["user_id"];

    // Verify the current account directly from the database.
    $stmt = mysqli_prepare(
        $conn,
        "SELECT id, role, is_active
         FROM users
         WHERE id = ?"
    );

    mysqli_stmt_bind_param($stmt, "i", $sessionUserId);
    mysqli_stmt_execute($stmt);

    $currentUser = mysqli_fetch_assoc(
        mysqli_stmt_get_result($stmt)
    );

    mysqli_stmt_close($stmt);

    if (
        $currentUser &&
        (int) $currentUser["is_active"] === 1 &&
        in_array($currentUser["role"], ["admin", "staff"], true)
    ) {
        $dashboard = $currentUser["role"] === "admin"
            ? "../admin/dashboard.php"
            : "../staff/dashboard.php";

        header("Location: " . $dashboard, true, 303);
        exit();
    }

    // Clear an invalid or deactivated account's session.
    $_SESSION = [];
    session_regenerate_id(true);
}

// =========================
// PROCESS LOGIN
// =========================
if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $loginUsername = is_string($_POST["username"] ?? null)
        ? trim($_POST["username"]) : "";

    $loginPassword = is_string($_POST["password"] ?? null)
        ? $_POST["password"] : "";

    if ($loginUsername === "" || $loginPassword === "") {
        http_response_code(400);
        exit("Please fill in all fields.");
    }

    // Find the account using username or email
    $stmt = mysqli_prepare(
        $conn,
        "SELECT *,
                COALESCE(
                    GREATEST(
                        0,
                        TIMESTAMPDIFF(SECOND, NOW(), locked_until)
                    ),
                    0
                ) AS remaining_seconds
         FROM users
         WHERE username = ? OR email = ?"
    );

    mysqli_stmt_bind_param(
        $stmt,
        "ss",
        $loginUsername,
        $loginUsername
    );

    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);

    // Reject missing or ambiguous accounts
    if (mysqli_num_rows($result) !== 1) {
        mysqli_stmt_close($stmt);
        http_response_code(401);
        exit("Invalid username or password.");
    }

    $user = mysqli_fetch_assoc($result);
    mysqli_stmt_close($stmt);

    $userId = (int) $user["id"];

    // Inactive accounts cannot log in
    if ((int) $user["is_active"] !== 1) {
        http_response_code(403);
        exit("Account deactivated. Contact your gym administrator.");
    }

    // Send remaining lock time to JavaScript
    if ((int) $user["remaining_seconds"] > 0) {
        http_response_code(429);
        exit(
            "Account temporarily locked.|" .
            (int) $user["remaining_seconds"]
        );
    }

    // Reset attempts after the lock expires
    if ($user["locked_until"] !== null) {
        $stmt = mysqli_prepare(
            $conn,
            "UPDATE users
             SET failed_attempts = 0, locked_until = NULL
             WHERE id = ?"
        );

        mysqli_stmt_bind_param($stmt, "i", $userId);
        mysqli_stmt_execute($stmt);
        mysqli_stmt_close($stmt);

        $user["failed_attempts"] = 0;
    }

    // Support existing plain passwords and hashed passwords
    $storedPassword = $user["password"];
    $passwordInfo = password_get_info($storedPassword);
    $isHashed = $passwordInfo["algoName"] !== "unknown";

    $passwordCorrect = $isHashed
        ? password_verify($loginPassword, $storedPassword)
        : hash_equals($storedPassword, $loginPassword);

    if (!$passwordCorrect) {
        $failedAttempts = (int) $user["failed_attempts"] + 1;

        // Lock for 60 seconds after five failures
        if ($failedAttempts >= 5) {
            $stmt = mysqli_prepare(
                $conn,
                "UPDATE users
                 SET failed_attempts = 5,
                     locked_until = DATE_ADD(NOW(), INTERVAL 60 SECOND)
                 WHERE id = ?"
            );

            mysqli_stmt_bind_param($stmt, "i", $userId);
            mysqli_stmt_execute($stmt);
            mysqli_stmt_close($stmt);

            http_response_code(429);
            exit("Account temporarily locked.|60");
        }

        $stmt = mysqli_prepare(
            $conn,
            "UPDATE users SET failed_attempts = ? WHERE id = ?"
        );

        mysqli_stmt_bind_param(
            $stmt,
            "ii",
            $failedAttempts,
            $userId
        );

        mysqli_stmt_execute($stmt);
        mysqli_stmt_close($stmt);

        http_response_code(401);
        exit("Invalid username or password.");
    }

    // Allow only the two supported roles
    if (!in_array($user["role"], ["admin", "staff"], true)) {
        http_response_code(403);
        exit("Account access is unavailable. Contact your gym administrator.");
    }

    // Upgrade existing plain-text passwords after valid login
    if (!$isHashed) {
        $passwordHash = password_hash(
            $loginPassword,
            PASSWORD_DEFAULT
        );

        $stmt = mysqli_prepare(
            $conn,
            "UPDATE users SET password = ? WHERE id = ?"
        );

        mysqli_stmt_bind_param(
            $stmt,
            "si",
            $passwordHash,
            $userId
        );

        mysqli_stmt_execute($stmt);
        mysqli_stmt_close($stmt);
    }

    // Reset failures after successful login
    $stmt = mysqli_prepare(
        $conn,
        "UPDATE users
         SET failed_attempts = 0, locked_until = NULL
         WHERE id = ?"
    );

    mysqli_stmt_bind_param($stmt, "i", $userId);
    mysqli_stmt_execute($stmt);
    mysqli_stmt_close($stmt);

    // Create a fresh authenticated session
    session_regenerate_id(true);
    $_SESSION = [];

    $_SESSION["user_id"] = $userId;
    $_SESSION["username"] = $user["username"];
    $_SESSION["role"] = $user["role"];
    $_SESSION["csrf_token"] = bin2hex(random_bytes(32));

    // Open the correct dashboard
    if ($user["role"] === "admin") {
        header("Location: ../admin/dashboard.php", true, 303);
    } else {
        header("Location: ../staff/dashboard.php", true, 303);
    }

    exit();
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PeakGym Management</title>
    <link rel="stylesheet" href="style.css?v=3">
    <link rel="icon" type="image/png" href="/Payapaya_Security1/assets/favicon.png">
</head>

<body>
    <main class="page">

        <!-- NAVIGATION -->
        <header class="navbar">
            <div class="logo">PEAKGYM</div>

            <nav class="nav-links">
                <a href="#">About</a>
                <a href="#">Security</a>
                <a href="#">Help</a>
            </nav>
        </header>

        <!-- LOGIN SECTION -->
        <section class="auth">

            <div class="intro">
                <p class="label">PEAKGYM MANAGEMENT</p>

                <h1>
                    Manage your gym.<br>
                    <span>Keep it moving.</span>
                </h1>

                <p class="description">
                    Your space for managing members, attendance,
                    and everyday gym operations.
                </p>
            </div>

            <div class="card">
                <div class="login">
                    <h2>Log In</h2>

                    <p class="subtext">
                        Access your PeakGym management account.
                    </p>

                    <form method="POST" action="login.php" id="loginForm">
                        <label for="loginEmail">Username or Email</label>

                        <input
                            type="text"
                            id="loginEmail"
                            name="username"
                            autocomplete="username"
                        >

                        <label for="loginPassword">Password</label>

                        <div class="password-wrapper">
                            <input
                                type="password"
                                id="loginPassword"
                                name="password"
                                autocomplete="current-password"
                            >

                            <button
                                type="button"
                                id="togglePassword"
                                class="toggle-password"
                                aria-label="Show password"
                            >
                                <svg viewBox="0 0 24 24" aria-hidden="true">
                                    <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"></path>
                                    <circle cx="12" cy="12" r="2.5"></circle>
                                </svg>
                            </button>
                        </div>

                        <!-- These existing features are not connected yet -->
                        <div class="options">
                            <label>
                                <input type="checkbox">
                                Remember me
                            </label>

                            <a href="#">Forgot password?</a>
                        </div>

                        <p
                            class="error-message"
                            id="loginError"
                            aria-live="polite"
                        ></p>

                        <button type="submit" id="loginSubmit">
                            LOG IN
                        </button>
                    </form>

                    <p class="switch">
                        Need an account?
                        <span class="admin-contact">
                            Contact your gym administrator.
                        </span>
                    </p>
                </div>
            </div>
        </section>
    </main>

    <script src="script.js?v=5"></script>

    <script>
        // Recheck the session if Back restores a cached login page.
        window.addEventListener("pageshow", function (event) {
            if (event.persisted) {
                window.location.reload();
            }
        });
    </script>
</body>
</html>