<?php
session_start();

header("Cache-Control: no-store");
date_default_timezone_set("Asia/Manila");

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
    http_response_code(500);
    exit("Unable to connect to the database.");
}

mysqli_set_charset($conn, "utf8mb4");

// =========================
// CHECK CURRENT ADMIN
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

// =========================
// CSRF TOKEN
// =========================
if (empty($_SESSION["csrf_token"])) {
    $_SESSION["csrf_token"] = bin2hex(random_bytes(32));
}

// =========================
// PROCESS LOGOUT
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

    if (($_POST["action"] ?? "") !== "logout") {
        http_response_code(400);
        exit("Invalid action.");
    }

    $_SESSION = [];

    if (ini_get("session.use_cookies")) {
        $params = session_get_cookie_params();

        setcookie(
            session_name(),
            "",
            time() - 42000,
            $params["path"],
            $params["domain"],
            $params["secure"],
            $params["httponly"]
        );
    }

    session_destroy();

    header("Location: ../auth/login.php", true, 303);
    exit();
}

// =========================
// STAFF SUMMARY
// =========================
$sql = "SELECT
            COUNT(*) AS total_staff,
            COUNT(CASE WHEN is_active = 1 THEN 1 END) AS active_staff,
            COUNT(CASE WHEN is_active = 0 THEN 1 END) AS inactive_staff
        FROM users
        WHERE role = 'staff'";

$result = mysqli_query($conn, $sql);
$counts = mysqli_fetch_assoc($result);

// =========================
// MEMBERSHIP SUMMARY
// =========================
$today = date("Y-m-d");

$membershipCounts = [
    "total" => 0,
    "active" => 0,
    "expiring_today" => 0,
    "expired" => 0
];

// Return one row per member, including members with several renewals.
$stmt = mysqli_prepare(
    $conn,
    "SELECT
        m.id,
        MAX(
            CASE
                WHEN ms.start_date <= ?
                 AND ms.due_date >= ?
                THEN 1
                ELSE 0
            END
        ) AS is_active,
        MAX(
            CASE
                WHEN ms.start_date <= ?
                 AND ms.due_date = ?
                THEN 1
                ELSE 0
            END
        ) AS expires_today,
        MAX(ms.due_date) AS last_due
     FROM members AS m
     LEFT JOIN memberships AS ms
        ON ms.member_id = m.id
     GROUP BY m.id"
);

mysqli_stmt_bind_param(
    $stmt,
    "ssss",
    $today,
    $today,
    $today,
    $today
);

mysqli_stmt_execute($stmt);

$membershipResult = mysqli_stmt_get_result($stmt);

while ($membership = mysqli_fetch_assoc($membershipResult)) {
    $membershipCounts["total"]++;

    if ((int) $membership["is_active"] === 1) {
        $membershipCounts["active"]++;
    }

    if ((int) $membership["expires_today"] === 1) {
        $membershipCounts["expiring_today"]++;
    }

    // Members with an upcoming renewal are not counted as expired.
    if (
        $membership["last_due"] !== null &&
        $membership["last_due"] < $today
    ) {
        $membershipCounts["expired"]++;
    }
}

mysqli_stmt_close($stmt);

// =========================
// HTML OUTPUT HELPER
// =========================
function escapeHtml($value) {
    return htmlspecialchars((string) $value, ENT_QUOTES, "UTF-8");
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>Admin Dashboard | PeakGym</title>

    <link rel="stylesheet" href="dashboard_style.css?v=9">
</head>

<body>
    <div class="layout">

        <!-- SIDEBAR -->
        <aside class="sidebar">
            <div class="logo">PEAKGYM</div>
            <p class="sidebar-caption">Management System</p>

            <nav class="navigation" aria-label="Admin navigation">
                <a
                    href="dashboard.php"
                    class="active"
                    aria-current="page"
                >
                    Dashboard
                </a>

                <a href="user_management/user_management.php">
                    Staff Management
                </a>

                <a href="../staff/monthly_members/monthly_members.php">
                    Monthly Members
                </a>
            </nav>

            <!-- ADMIN PROFILE -->
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

                        <p class="account-role">
                            PeakGym Administrator
                        </p>
                    </div>
                </div>

                <form
                    method="POST"
                    action="dashboard.php"
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

        <!-- DASHBOARD CONTENT -->
        <main class="main">
            <header class="page-header">
                <h1>Dashboard</h1>

                <p class="description">
                    Your PeakGym staff and membership overview.
                </p>
            </header>

            <!-- FIRST: STAFF OVERVIEW -->
            <section
                class="staff-overview"
                aria-labelledby="staffOverviewTitle"
            >

            <div class="section-heading staff-heading">
                <h2 id="staffOverviewTitle">
                    Staff overview
                </h2>

                <a
                    href="user_management/user_management.php"
                    class="staff-link"
                >
                    View staff accounts
                </a>
            </div>

                <div class="stats">
                    <article class="stat">
                        <h3 class="stat-label">
                            Total staff
                        </h3>

                        <p class="stat-number">
                            <?php echo (int) $counts["total_staff"]; ?>
                        </p>

                        <p class="stat-note">
                            All registered staff accounts
                        </p>
                    </article>

                    <article class="stat">
                        <h3 class="stat-label">
                            Active staff
                        </h3>

                        <p class="stat-number green">
                            <?php echo (int) $counts["active_staff"]; ?>
                        </p>

                        <p class="stat-note">
                            Staff accounts with active access
                        </p>
                    </article>

                    <article class="stat">
                        <h3 class="stat-label">
                            Inactive staff
                        </h3>

                        <p class="stat-number yellow">
                            <?php echo (int) $counts["inactive_staff"]; ?>
                        </p>

                        <p class="stat-note">
                            Deactivated staff accounts
                        </p>
                    </article>
                </div>

            </section>

            <!-- SECOND: MEMBERSHIP OVERVIEW -->
            <section
                class="membership-overview"
                aria-labelledby="membershipOverviewTitle"
            >
                <div class="section-heading">
                    <h2 id="membershipOverviewTitle">
                        Membership overview
                    </h2>

                    <p>
                        As of <?php echo date("M j, Y"); ?>
                    </p>
                </div>

                <div class="membership-summary-grid">
                    <article class="membership-summary-card">
                        <h3 class="membership-summary-label">
                            Total members
                        </h3>

                        <p class="membership-summary-number">
                            <?php echo (int) $membershipCounts["total"]; ?>
                        </p>

                        <p class="membership-summary-note">
                            All registered members
                        </p>
                    </article>

                    <article class="membership-summary-card">
                        <h3 class="membership-summary-label">
                            Active memberships
                        </h3>

                        <p class="membership-summary-number green">
                            <?php echo (int) $membershipCounts["active"]; ?>
                        </p>

                        <p class="membership-summary-note">
                            Valid for a workout today
                        </p>
                    </article>

                    <article class="membership-summary-card">
                        <h3 class="membership-summary-label">
                            Expiring today
                        </h3>

                        <p class="membership-summary-number yellow">
                            <?php echo (int) $membershipCounts["expiring_today"]; ?>
                        </p>

                        <p class="membership-summary-note">
                            Current period ends today
                        </p>
                    </article>

                    <article class="membership-summary-card">
                        <h3 class="membership-summary-label">
                            Expired memberships
                        </h3>

                        <p class="membership-summary-number red">
                            <?php echo (int) $membershipCounts["expired"]; ?>
                        </p>

                        <p class="membership-summary-note">
                            Ended with no upcoming renewal
                        </p>
                    </article>
                </div>
            </section>
        </main>
    </div>

    <script src="dashboard_script.js?v=1"></script>
</body>
</html>