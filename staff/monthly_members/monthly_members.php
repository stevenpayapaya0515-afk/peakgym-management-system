<?php

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

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
$host = "localhost";
$username = "root";
$password = "";
$dbname = "security_1";

try {
    $conn = mysqli_connect(
        $host,
        $username,
        $password,
        $dbname
    );

    mysqli_set_charset($conn, "utf8mb4");
} catch (mysqli_sql_exception $exception) {
    error_log($exception->getMessage());

    http_response_code(500);
    exit("Database connection failed.");
}

// =========================
// CHECK STAFF ACCOUNT
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

$staff = mysqli_fetch_assoc(
    mysqli_stmt_get_result($stmt)
);

mysqli_stmt_close($stmt);

if (!$staff || (int) $staff["is_active"] !== 1) {
    $_SESSION = [];
    session_destroy();

    header("Location: ../../auth/login.php");
    exit();
}

// Allow active admin and staff accounts.
// The active-account check above remains in place.
if (!in_array($staff["role"], ["admin", "staff"], true)) {
    http_response_code(403);
    exit("Access denied.");
}

// Use the role retrieved from the database.
$isAdmin = $staff["role"] === "admin";

$dashboardUrl = $isAdmin
    ? "../../admin/dashboard.php"
    : "../dashboard.php";

$roleLabel = $isAdmin
    ? "PeakGym Administrator"
    : "PeakGym Staff";

$navigationLabel = $isAdmin
    ? "Admin navigation"
    : "Staff navigation";

if (empty($_SESSION["csrf_token"])) {
    $_SESSION["csrf_token"] = bin2hex(random_bytes(32));
}

// =========================
// HELPER FUNCTIONS
// =========================
function escapeHtml($value)
{
    return htmlspecialchars(
        (string) $value,
        ENT_QUOTES,
        "UTF-8"
    );
}

function validDate($value)
{
    if (
        !is_string($value) ||
        !preg_match('/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/D', $value)
    ) {
        return false;
    }

    $date = DateTimeImmutable::createFromFormat(
        "!Y-m-d",
        $value
    );

    return $date && $date->format("Y-m-d") === $value;
}

function calculateDueDate($value)
{
    $start = new DateTimeImmutable($value);
    $nextMonth = $start->modify("first day of next month");

    $day = min(
        (int) $start->format("d"),
        (int) $nextMonth->format("t")
    );

    return $nextMonth->setDate(
        (int) $nextMonth->format("Y"),
        (int) $nextMonth->format("m"),
        $day
    )->format("Y-m-d");
}

function displayDate($value)
{
    return (new DateTimeImmutable($value))->format("M j, Y");
}

// =========================
// PRIVATE PHOTO STORAGE
// =========================
function photoDirectory()
{
    $configured = getenv("PEAKGYM_PHOTO_DIR");
    $root = realpath($_SERVER["DOCUMENT_ROOT"] ?? "");

    if (!$root) {
        throw new RuntimeException(
            "Cannot locate the website folder."
        );
    }

    $directory = $configured ?: (
        dirname($root) .
        "/peakgym-private/" .
        substr(hash("sha256", __DIR__), 0, 16)
    );

    if (
        !is_dir($directory) &&
        !@mkdir($directory, 0700, true) &&
        !is_dir($directory)
    ) {
        throw new RuntimeException(
            "Cannot create the photo folder. Check its write permission."
        );
    }

    $resolved = realpath($directory);

    if (!$resolved) {
        throw new RuntimeException(
            "Cannot access the photo folder."
        );
    }

    $public = strtolower(str_replace("\\", "/", $root));
    $private = strtolower(str_replace("\\", "/", $resolved));

    if (
        $private === $public ||
        strpos($private, rtrim($public, "/") . "/") === 0
    ) {
        throw new RuntimeException(
            "The photo folder must be outside the public website folder."
        );
    }

    return $resolved;
}

function photoPath($filename)
{
    if (
        !is_string($filename) ||
        !preg_match('/^[a-f0-9]{32}\.(jpg|png)$/D', $filename)
    ) {
        return null;
    }

    return photoDirectory() . DIRECTORY_SEPARATOR . $filename;
}

function photoUrl($member)
{
    if (empty($member["photo"])) {
        return "";
    }

    return "monthly_members.php?photo=" . (int) $member["id"];
}

function removePhoto($filename)
{
    if (!$filename) {
        return;
    }

    try {
        $path = photoPath($filename);

        if ($path && is_file($path)) {
            @unlink($path);
        }
    } catch (Throwable $exception) {
        error_log("Member photo cleanup failed.");
    }
}

// =========================
// VALIDATE AND SAVE PHOTO
// =========================
function savePhoto()
{
    if (!isset($_FILES["photo"])) {
        return null;
    }

    $file = $_FILES["photo"];

    if (
        !is_array($file) ||
        !isset($file["error"]) ||
        !is_int($file["error"])
    ) {
        throw new RuntimeException("Invalid photo upload.");
    }

    if ($file["error"] === UPLOAD_ERR_NO_FILE) {
        return null;
    }

    if ($file["error"] !== UPLOAD_ERR_OK) {
        throw new RuntimeException(
            "Photo upload failed. Choose a PNG or JPEG up to 2 MB."
        );
    }

    if (
        !is_string($file["tmp_name"] ?? null) ||
        !is_uploaded_file($file["tmp_name"])
    ) {
        throw new RuntimeException("Invalid photo upload.");
    }

    $size = filesize($file["tmp_name"]);

    if (!$size || $size > 2 * 1024 * 1024) {
        throw new RuntimeException(
            "Photo must be 2 MB or smaller."
        );
    }

    if (!extension_loaded("gd") || !class_exists("finfo")) {
        throw new RuntimeException(
            "Enable gd and fileinfo in XAMPP php.ini, then restart Apache."
        );
    }

    $mime = (new finfo(FILEINFO_MIME_TYPE))->file(
        $file["tmp_name"]
    );

    $info = @getimagesize($file["tmp_name"]);

    if (
        !in_array($mime, ["image/jpeg", "image/png"], true) ||
        !$info ||
        $info["mime"] !== $mime
    ) {
        throw new RuntimeException(
            "Choose a valid PNG or JPEG image."
        );
    }

    if (
        $info[0] < 1 ||
        $info[1] < 1 ||
        $info[0] > 5000 ||
        $info[1] > 5000 ||
        $info[0] * $info[1] > 12000000
    ) {
        throw new RuntimeException(
            "Photo is too large. Use an image below 5000 pixels per side and 12 megapixels."
        );
    }

    // Decode the image instead of trusting the uploaded filename.
    $source = $mime === "image/png"
        ? @imagecreatefrompng($file["tmp_name"])
        : @imagecreatefromjpeg($file["tmp_name"]);

    if (!$source) {
        throw new RuntimeException(
            "Cannot read this image. Choose another photo."
        );
    }

    $clean = null;
    $path = null;
    $saved = false;

    try {
        $scale = min(1, 1200 / max($info[0], $info[1]));

        $width = max(1, (int) round($info[0] * $scale));
        $height = max(1, (int) round($info[1] * $scale));

        $clean = imagecreatetruecolor($width, $height);

        if (!$clean) {
            throw new RuntimeException(
                "Cannot process this photo."
            );
        }

        imagealphablending($clean, false);
        imagesavealpha($clean, true);

        $copied = imagecopyresampled(
            $clean,
            $source,
            0,
            0,
            0,
            0,
            $width,
            $height,
            $info[0],
            $info[1]
        );

        if (!$copied) {
            throw new RuntimeException(
                "Cannot process this photo."
            );
        }

        $extension = $mime === "image/png" ? ".png" : ".jpg";
        $filename = bin2hex(random_bytes(16)) . $extension;
        $path = photoPath($filename);

        $saved = $mime === "image/png"
            ? @imagepng($clean, $path)
            : @imagejpeg($clean, $path, 85);

        if (!$saved) {
            throw new RuntimeException(
                "Cannot save the photo. Check the photo folder's write permission."
            );
        }

        return $filename;
    } finally {
        imagedestroy($source);

        if ($clean) {
            imagedestroy($clean);
        }

        if (!$saved && $path && is_file($path)) {
            @unlink($path);
        }
    }
}

// =========================
// DISPLAY SAVED PHOTO
// =========================
if (
    $_SERVER["REQUEST_METHOD"] === "GET" &&
    isset($_GET["photo"])
) {
    $photoId = filter_var(
        $_GET["photo"],
        FILTER_VALIDATE_INT
    );

    if (!$photoId || $photoId < 1) {
        http_response_code(404);
        exit();
    }

    $stmt = mysqli_prepare(
        $conn,
        "SELECT photo FROM members WHERE id = ?"
    );

    mysqli_stmt_bind_param($stmt, "i", $photoId);
    mysqli_stmt_execute($stmt);

    $record = mysqli_fetch_assoc(
        mysqli_stmt_get_result($stmt)
    );

    mysqli_stmt_close($stmt);

    try {
        $path = photoPath($record["photo"] ?? null);
    } catch (RuntimeException $exception) {
        http_response_code(404);
        exit();
    }

    if (!$path || !is_file($path)) {
        http_response_code(404);
        exit();
    }

    $contentType = pathinfo($path, PATHINFO_EXTENSION) === "png"
        ? "image/png"
        : "image/jpeg";

    header("Content-Type: " . $contentType);
    header("X-Content-Type-Options: nosniff");
    header("Content-Length: " . filesize($path));

    session_write_close();
    readfile($path);
    exit();
}

// =========================
// PAGE MESSAGES
// =========================
$today = date("Y-m-d");
$error = "";

$success = $_SESSION["member_success"] ?? "";
unset($_SESSION["member_success"]);


// =========================
// DELETE MEMBER
// =========================
if (
    $_SERVER["REQUEST_METHOD"] === "POST" &&
    ($_POST["action"] ?? "") === "delete"
) {
    $token = $_POST["csrf_token"] ?? "";

    if (
        !is_string($token) ||
        !hash_equals($_SESSION["csrf_token"], $token)
    ) {
        http_response_code(403);
        exit("Invalid request. Refresh the page and try again.");
    }

    $deleteId = filter_var(
        $_POST["member_id"] ?? "",
        FILTER_VALIDATE_INT
    );

    $deleteTransaction = false;
    $deletedPhoto = null;

    try {
        if (!$deleteId || $deleteId < 1) {
            throw new RuntimeException("Invalid member.");
        }

        mysqli_begin_transaction($conn);
        $deleteTransaction = true;

        // Lock the member while deleting their records.
        $stmt = mysqli_prepare(
            $conn,
            "SELECT id, photo
             FROM members
             WHERE id = ?
             FOR UPDATE"
        );

        mysqli_stmt_bind_param($stmt, "i", $deleteId);
        mysqli_stmt_execute($stmt);

        $memberToDelete = mysqli_fetch_assoc(
            mysqli_stmt_get_result($stmt)
        );

        mysqli_stmt_close($stmt);

        if (!$memberToDelete) {
            throw new RuntimeException(
                "This member no longer exists."
            );
        }

        $deletedPhoto = $memberToDelete["photo"];

        // Delete related membership records first.
        $stmt = mysqli_prepare(
            $conn,
            "DELETE FROM memberships WHERE member_id = ?"
        );

        mysqli_stmt_bind_param($stmt, "i", $deleteId);
        mysqli_stmt_execute($stmt);
        mysqli_stmt_close($stmt);

        // Then delete the member.
        $stmt = mysqli_prepare(
            $conn,
            "DELETE FROM members WHERE id = ?"
        );

        mysqli_stmt_bind_param($stmt, "i", $deleteId);
        mysqli_stmt_execute($stmt);
        mysqli_stmt_close($stmt);

        mysqli_commit($conn);
        $deleteTransaction = false;
    } catch (Throwable $exception) {
        if ($deleteTransaction) {
            mysqli_rollback($conn);
        }

        if (
            $exception instanceof RuntimeException &&
            !($exception instanceof mysqli_sql_exception)
        ) {
            $error = $exception->getMessage();
        } else {
            error_log($exception->getMessage());

            $error = "Unable to delete this member. Please try again.";
        }
    }

    if ($error === "") {
        // Remove the saved photo only after database deletion succeeds.
        removePhoto($deletedPhoto);

        $_SESSION["member_success"] =
            "Member and membership history deleted successfully.";

        header("Location: monthly_members.php", true, 303);
        exit();
    }
}

// =========================
// ADD / EDIT / RENEW
// =========================
if (
    $_SERVER["REQUEST_METHOD"] === "POST" &&
    ($_POST["action"] ?? "") !== "delete"
) {
    $token = $_POST["csrf_token"] ?? "";

    if (
        !is_string($token) ||
        !hash_equals($_SESSION["csrf_token"], $token)
    ) {
        http_response_code(403);

        exit(
            "Invalid or oversized request. Refresh and try a photo under 2 MB."
        );
    }

    $action = $_POST["action"] ?? "";

    $name = is_string($_POST["full_name"] ?? null)
        ? trim($_POST["full_name"])
        : "";

    $start = is_string($_POST["start_date"] ?? null)
        ? $_POST["start_date"]
        : "";

    $due = is_string($_POST["due_date"] ?? null)
        ? $_POST["due_date"]
        : "";

    $memberId = filter_var(
        $_POST["member_id"] ?? "",
        FILTER_VALIDATE_INT
    );

    $periodId = filter_var(
        $_POST["membership_id"] ?? "",
        FILTER_VALIDATE_INT
    );

    $newPhoto = null;
    $oldPhoto = null;
    $transaction = false;

    try {
        if (!in_array($action, ["add", "edit", "renew"], true)) {
            throw new RuntimeException("Invalid action.");
        }

        if (
            $action !== "renew" &&
            ($name === "" || mb_strlen($name, "UTF-8") > 100)
        ) {
            throw new RuntimeException(
                "Enter a member name with 1–100 characters."
            );
        }

        if (
            !validDate($start) ||
            $start < "1900-01-01" ||
            $start > "2099-12-31"
        ) {
            throw new RuntimeException(
                "Choose a valid start date between 1900 and 2099."
            );
        }

        // Add and Renew always calculate one calendar month.
        // Edit allows correction of the saved due date.
        if ($action !== "edit") {
            $due = calculateDueDate($start);
        }

        if (
            !validDate($due) ||
            $due < $start ||
            $due > "2100-12-31"
        ) {
            throw new RuntimeException(
                "Due date must be on or after the start date, no later than 2100."
            );
        }

        if (
            $action !== "add" &&
            (!$memberId || $memberId < 1)
        ) {
            throw new RuntimeException("Invalid member.");
        }

        if (
            $action === "edit" &&
            (!$periodId || $periodId < 1)
        ) {
            throw new RuntimeException(
                "Choose an existing membership to edit."
            );
        }

        mysqli_begin_transaction($conn);
        $transaction = true;

        // Lock the member to prevent conflicting updates.
        if ($action !== "add") {
            $stmt = mysqli_prepare(
                $conn,
                "SELECT id, photo
                 FROM members
                 WHERE id = ?
                 FOR UPDATE"
            );

            mysqli_stmt_bind_param($stmt, "i", $memberId);
            mysqli_stmt_execute($stmt);

            $record = mysqli_fetch_assoc(
                mysqli_stmt_get_result($stmt)
            );

            mysqli_stmt_close($stmt);

            if (!$record) {
                throw new RuntimeException("Member not found.");
            }

            $oldPhoto = $record["photo"];
        }

        // Ensure the edited period belongs to this member.
        if ($action === "edit") {
            $stmt = mysqli_prepare(
                $conn,
                "SELECT id
                 FROM memberships
                 WHERE id = ? AND member_id = ?
                 FOR UPDATE"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "ii",
                $periodId,
                $memberId
            );

            mysqli_stmt_execute($stmt);

            $record = mysqli_fetch_assoc(
                mysqli_stmt_get_result($stmt)
            );

            mysqli_stmt_close($stmt);

            if (!$record) {
                throw new RuntimeException(
                    "This membership does not belong to the selected member."
                );
            }
        }

        // Reject overlapping periods, including the last valid day.
        if ($action !== "add") {
            $excludeId = $action === "edit" ? $periodId : 0;

            $stmt = mysqli_prepare(
                $conn,
                "SELECT id
                 FROM memberships
                 WHERE member_id = ?
                   AND id <> ?
                   AND start_date <= ?
                   AND due_date >= ?
                 LIMIT 1"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "iiss",
                $memberId,
                $excludeId,
                $due,
                $start
            );

            mysqli_stmt_execute($stmt);

            $overlap = mysqli_fetch_assoc(
                mysqli_stmt_get_result($stmt)
            );

            mysqli_stmt_close($stmt);

            if ($overlap) {
                throw new RuntimeException(
                    "These dates overlap another membership period."
                );
            }
        }

        if ($action === "renew") {
            $stmt = mysqli_prepare(
                $conn,
                "SELECT MAX(due_date) AS last_due
                 FROM memberships
                 WHERE member_id = ?"
            );

            mysqli_stmt_bind_param($stmt, "i", $memberId);
            mysqli_stmt_execute($stmt);

            $last = mysqli_fetch_assoc(
                mysqli_stmt_get_result($stmt)
            );

            mysqli_stmt_close($stmt);

            if (
                $last["last_due"] &&
                $start <= $last["last_due"]
            ) {
                throw new RuntimeException(
                    "Renewal must start after " .
                    displayDate($last["last_due"]) .
                    "."
                );
            }
        }

        if ($action !== "renew") {
            $newPhoto = savePhoto();
        }

        // Keep the old photo if no replacement was uploaded.
        $photo = $newPhoto ?? $oldPhoto;

        if ($action === "add") {
            $stmt = mysqli_prepare(
                $conn,
                "INSERT INTO members (full_name, photo)
                 VALUES (?, ?)"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "ss",
                $name,
                $photo
            );

            mysqli_stmt_execute($stmt);
            $memberId = mysqli_insert_id($conn);

            mysqli_stmt_close($stmt);
        } elseif ($action === "edit") {
            $stmt = mysqli_prepare(
                $conn,
                "UPDATE members
                 SET full_name = ?, photo = ?
                 WHERE id = ?"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "ssi",
                $name,
                $photo,
                $memberId
            );

            mysqli_stmt_execute($stmt);
            mysqli_stmt_close($stmt);
        }

        if ($action === "edit") {
            $stmt = mysqli_prepare(
                $conn,
                "UPDATE memberships
                 SET start_date = ?, due_date = ?
                 WHERE id = ? AND member_id = ?"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "ssii",
                $start,
                $due,
                $periodId,
                $memberId
            );
        } else {
            $stmt = mysqli_prepare(
                $conn,
                "INSERT INTO memberships
                    (member_id, start_date, due_date)
                 VALUES (?, ?, ?)"
            );

            mysqli_stmt_bind_param(
                $stmt,
                "iss",
                $memberId,
                $start,
                $due
            );
        }

        mysqli_stmt_execute($stmt);
        mysqli_stmt_close($stmt);

        mysqli_commit($conn);
        $transaction = false;
    } catch (Throwable $exception) {
        if ($transaction) {
            mysqli_rollback($conn);
        }

        removePhoto($newPhoto);

        if (
            $exception instanceof RuntimeException &&
            !($exception instanceof mysqli_sql_exception)
        ) {
            $error = $exception->getMessage();
        } else {
            error_log($exception->getMessage());

            $error = "Unable to save. Please try again.";
        }
    }

    if ($error === "") {
        if ($newPhoto && $oldPhoto) {
            removePhoto($oldPhoto);
        }

        $_SESSION["member_success"] = match ($action) {
            "add" => "Member added successfully.",
            "edit" => "Member details updated successfully.",
            "renew" => "Membership renewed successfully."
        };

        header("Location: monthly_members.php", true, 303);
        exit();
    }
}

// =========================
// LOAD MEMBERS AND HISTORY
// =========================
$members = mysqli_fetch_all(
    mysqli_query(
        $conn,
        "SELECT id, full_name, photo
         FROM members
         ORDER BY id DESC"
    ),
    MYSQLI_ASSOC
);

$periods = mysqli_fetch_all(
    mysqli_query(
        $conn,
        "SELECT id, member_id, start_date, due_date
         FROM memberships
         ORDER BY start_date DESC, id DESC"
    ),
    MYSQLI_ASSOC
);

$history = [];

foreach ($periods as $period) {
    $history[$period["member_id"]][] = $period;
}

?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Monthly Members | PeakGym</title>
    <link rel="stylesheet" href="../dashboard_style.css?v=1">
    <link rel="stylesheet" href="monthly_members_style.css?v=11">
</head>

<body>
    <div class="layout">

        <!-- SIDEBAR -->
        <aside class="sidebar">
            <div class="logo">PEAKGYM</div>

            <p class="sidebar-caption">
                Management System
            </p>

            <nav class="navigation"
                aria-label="<?php echo escapeHtml($navigationLabel); ?>">

                <a href="<?php echo escapeHtml($dashboardUrl); ?>">
                    Dashboard
                </a>

                <?php if ($isAdmin): ?>
                    <a href="../../admin/user_management/user_management.php">
                        Staff Management
                    </a>
                <?php endif; ?>

                <a href="monthly_members.php"
                class="active"
                aria-current="page">
                    Monthly Members
                </a>

                <?php if ($staff["role"] === "staff"): ?>
                    <a href="../settings/settings.php">
                        Settings
                    </a>
                <?php endif; ?>
            </nav>

            <!-- ACCOUNT PROFILE -->
            <div class="account">
                <div class="account-profile">
                    <div class="account-avatar" aria-hidden="true">
                        <svg viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="1.7"
                            stroke-linecap="round"
                            stroke-linejoin="round">

                            <circle cx="12" cy="8" r="4"></circle>

                            <path d="M4 21v-2a8 8 0 0 1 16 0v2"></path>
                        </svg>
                    </div>

                    <div class="account-details">
                        <p class="account-name">
                            <?php echo escapeHtml($staff["username"]); ?>
                        </p>

                        <p class="account-role">
                            <?php echo escapeHtml($roleLabel); ?>
                        </p>
                    </div>
                </div>

                <!-- LOGOUT -->
                <form method="POST"
                    action="<?php echo escapeHtml($dashboardUrl); ?>"
                    class="logout-form">

                    <input type="hidden"
                        name="action"
                        value="logout">

                    <input type="hidden"
                        name="csrf_token"
                        value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>">

                    <button type="submit" class="logout">
                        Log out
                    </button>
                </form>
            </div>
        </aside>

        <!-- MAIN CONTENT -->
        <main class="main">

            <header class="page-header">
                <h1>Monthly Members</h1>

                <p class="description">
                    Manage members, monthly renewals, and due dates.
                </p>
            </header>

            <?php if ($error !== ""): ?>
                <p class="member-error" role="alert">
                    <?php echo escapeHtml($error); ?>
                </p>
            <?php endif; ?>

            <!-- SEARCH AND ADD -->
            <div class="member-toolbar">
                <div class="member-search-box">
                    <svg viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.8"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true">
                        <circle cx="10.5" cy="10.5" r="6.5"></circle>
                        <path d="M16 16l4.5 4.5"></path>
                    </svg>

                    <input type="search"
                        id="memberSearch"
                        placeholder="Search member name..."
                        aria-label="Search member name">
                </div>

                <button type="button"
                        class="primary-button"
                        id="addMember"
                        aria-controls="memberPanel">
                    Add member
                </button>
            </div>

            <!-- INLINE FORM PANEL -->
            <section class="member-form-panel"
                     id="memberPanel"
                     aria-labelledby="memberPanelTitle"
                     hidden>

                <div class="member-panel-heading">
                    <div>
                        <h2 id="memberPanelTitle">Add member</h2>

                        <p id="memberPanelDescription">
                            Enter the member’s information.
                        </p>
                    </div>

                    <button type="button"
                            class="cancel-button"
                            id="closeMemberPanel">
                        Close
                    </button>
                </div>

                <form method="POST"
                      action="monthly_members.php"
                      enctype="multipart/form-data"
                      id="memberForm">

                    <input type="hidden"
                           name="csrf_token"
                           value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>">

                    <input type="hidden"
                           name="action"
                           id="memberAction">

                    <input type="hidden"
                           name="member_id"
                           id="memberId">

                    <input type="hidden"
                           name="membership_id"
                           id="membershipId">

                    <div class="member-editor-grid">

                        <!-- PHOTO -->
                        <div class="member-photo-field"
                             id="photoFields">

                            <span class="member-field-label">
                                Member photo
                            </span>

                            <div class="member-photo-preview">
                                <img id="photoPreview"
                                     alt="Member photo preview"
                                     hidden>

                                <span id="photoPlaceholder">
                                    No photo
                                </span>
                            </div>

                            <label class="photo-upload-button">
                                <span>Choose photo</span>

                                <input type="file"
                                       name="photo"
                                       id="memberPhoto"
                                       accept=".png,.jpg,.jpeg,image/png,image/jpeg"
                                       aria-label="Choose member photo"
                                       aria-describedby="photoHint">
                            </label>

                            <p class="photo-file-name"
                               id="photoFileName">
                                No file selected
                            </p>

                            <p class="member-field-hint"
                               id="photoHint">
                                Optional · PNG or JPEG · Up to 2 MB
                            </p>

                            <p class="member-photo-error"
                               id="photoError"
                               role="alert"
                               hidden></p>
                        </div>

                        <!-- NAME AND DATES -->
                        <div class="member-details-fields">
                            <div class="member-field">
                                <label for="memberName">
                                    Member name
                                </label>

                                <input type="text"
                                       name="full_name"
                                       id="memberName"
                                       maxlength="100"
                                       autocomplete="off"
                                       placeholder="Enter full name"
                                       required>
                            </div>

                            <div class="member-date-grid">
                                <div class="member-field">
                                    <label for="startDate">
                                        Start date
                                    </label>

                                    <input type="date"
                                           name="start_date"
                                           id="startDate"
                                           min="1900-01-01"
                                           max="2099-12-31"
                                           required>
                                </div>

                                <div class="member-field">
                                    <label for="dueDate">
                                        Due date
                                    </label>

                                    <input type="date"
                                           name="due_date"
                                           id="dueDate"
                                           min="1900-01-01"
                                           max="2100-12-31"
                                           required>
                                </div>
                            </div>

                            <p class="member-field-hint"
                               id="dateHint">
                                The due date is the last valid workout day.
                            </p>
                        </div>
                    </div>

                    <div class="member-panel-actions">
                        <button type="button"
                                class="cancel-button"
                                id="cancelMember">
                            Cancel
                        </button>

                        <button type="submit"
                                class="primary-button"
                                id="saveMember">
                            Save member
                        </button>
                    </div>
                </form>
            </section>

            <!-- MEMBER TABLE -->
            <div class="member-table overview-card">
                <table>
                    <thead>
                        <tr>
                            <th scope="col">Member</th>
                            <th scope="col">Start date</th>
                            <th scope="col">Due date</th>
                            <th scope="col">Status</th>
                            <th scope="col">Actions</th>
                        </tr>
                    </thead>

                    <tbody>
                        <?php foreach ($members as $member): ?>
                            <?php
                            $memberHistory = $history[$member["id"]] ?? [];

                            $shown = $memberHistory[0] ?? null;
                            $active = null;
                            $upcoming = null;

                            $status = "No membership";
                            $statusClass = "muted";

                            foreach ($memberHistory as $period) {
                                if (
                                    $period["start_date"] <= $today &&
                                    $period["due_date"] >= $today
                                ) {
                                    $active = $period;
                                    break;
                                }

                                if ($period["start_date"] > $today) {
                                    $upcoming = $period;
                                }
                            }

                            if ($active) {
                                $shown = $active;
                                $status = "Active";
                                $statusClass = "active-status";
                            } elseif ($upcoming) {
                                $shown = $upcoming;
                                $status = "Upcoming";
                                $statusClass = "upcoming-status";
                            } elseif ($shown) {
                                $status = "Expired";
                                $statusClass = "expired-status";
                            }

                            $lastDue = null;

                            foreach ($memberHistory as $period) {
                                if (
                                    $lastDue === null ||
                                    $period["due_date"] > $lastDue
                                ) {
                                    $lastDue = $period["due_date"];
                                }
                            }

                            $nextStart = $today;

                            if ($lastDue && $lastDue >= $today) {
                                $nextStart = (
                                    new DateTimeImmutable($lastDue)
                                )->modify("+1 day")->format("Y-m-d");
                            }
                            ?>

                            <tr class="member-row"
                                data-name="<?php echo escapeHtml($member["full_name"]); ?>">

                                <td>
                                    <div class="member-identity">
                                        <?php if ($member["photo"]): ?>
                                            <img class="member-thumbnail"
                                                 src="<?php echo escapeHtml(photoUrl($member)); ?>"
                                                 alt="Member photo"
                                                 loading="lazy">
                                        <?php else: ?>
                                            <span class="photo-placeholder"
                                                  aria-hidden="true">
                                                —
                                            </span>
                                        <?php endif; ?>

                                        <span class="member-name">
                                            <?php echo escapeHtml($member["full_name"]); ?>
                                        </span>
                                    </div>
                                </td>

                                <td class="member-date">
                                    <?php
                                    echo $shown
                                        ? displayDate($shown["start_date"])
                                        : "—";
                                    ?>
                                </td>

                                <td class="member-date">
                                    <?php
                                    echo $shown
                                        ? displayDate($shown["due_date"])
                                        : "—";
                                    ?>
                                </td>

                                <td>
                                    <span class="member-status <?php echo $statusClass; ?>">
                                        <?php echo $status; ?>
                                    </span>
                                </td>

                                <td>
                                    <div class="member-actions">
                                        <button type="button"
                                                class="edit-member"
                                                data-id="<?php echo (int) $member["id"]; ?>"
                                                data-name="<?php echo escapeHtml($member["full_name"]); ?>"
                                                data-period="<?php echo (int) ($shown["id"] ?? 0); ?>"
                                                data-start="<?php echo escapeHtml($shown["start_date"] ?? ""); ?>"
                                                data-due="<?php echo escapeHtml($shown["due_date"] ?? ""); ?>"
                                                data-photo="<?php echo escapeHtml(photoUrl($member)); ?>"
                                                <?php echo $shown ? "" : "disabled"; ?>>
                                            Edit
                                        </button>

                                        <button type="button"
                                                class="renew-member"
                                                data-id="<?php echo (int) $member["id"]; ?>"
                                                data-name="<?php echo escapeHtml($member["full_name"]); ?>"
                                                data-start="<?php echo $nextStart; ?>">
                                            Renew
                                        </button>

                                        <button type="button"
                                                class="history-button"
                                                data-target="history-<?php echo (int) $member["id"]; ?>">
                                            History
                                        </button>

                                        <button type="button"
                                                class="delete-member"
                                                data-id="<?php echo (int) $member["id"]; ?>"
                                                data-name="<?php echo escapeHtml($member["full_name"]); ?>">
                                            Delete
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        <?php endforeach; ?>

                        <tr id="emptyMembers"
                            <?php echo $members ? "hidden" : ""; ?>>

                            <td colspan="5" class="empty-message">
                                <?php
                                echo $members
                                    ? "No matching members."
                                    : "No members yet.";
                                ?>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </main>
    </div>

    <!-- HISTORY DIALOGS -->
    <?php foreach ($members as $member): ?>
        <dialog class="member-modal"
                id="history-<?php echo (int) $member["id"]; ?>"
                aria-labelledby="history-title-<?php echo (int) $member["id"]; ?>">

            <h2 id="history-title-<?php echo (int) $member["id"]; ?>">
                Membership history
            </h2>

            <p class="history-name">
                <?php echo escapeHtml($member["full_name"]); ?>
            </p>

            <div class="history-list">
            <div class="history-labels">
                <span>Start Date</span>
                <span aria-hidden="true"></span>
                <span>Due Date</span>
            </div>
                <?php foreach ($history[$member["id"]] ?? [] as $period): ?>
                    <div class="history-period">
                        <span>
                            <?php echo displayDate($period["start_date"]); ?>
                        </span>

                        <span class="history-arrow">→</span>

                        <span>
                            <?php echo displayDate($period["due_date"]); ?>
                        </span>
                    </div>
                <?php endforeach; ?>

                <?php if (empty($history[$member["id"]])): ?>
                    <p class="history-empty">
                        No membership records yet.
                    </p>
                <?php endif; ?>
            </div>

            <div class="modal-buttons">
                <button type="button"
                        class="cancel-button"
                        data-close>
                    Close
                </button>
            </div>
        </dialog>
    <?php endforeach; ?>

    <!-- SUCCESS DIALOG -->
    <?php if ($success !== ""): ?>
        <dialog class="member-modal success-modal"
                id="memberSuccess"
                aria-labelledby="memberSuccessTitle">

            <h2 id="memberSuccessTitle">Successful!</h2>

            <p><?php echo escapeHtml($success); ?></p>

            <form method="dialog">
                <button type="submit"
                        class="primary-button"
                        autofocus>
                    Okay
                </button>
            </form>
        </dialog>
    <?php endif; ?>

    <script src="../dashboard_script.js?v=1"></script>

    <!-- DELETE CONFIRMATION -->
    <dialog class="member-modal delete-member-modal"
            id="deleteMemberModal"
            aria-labelledby="deleteMemberTitle"
            aria-describedby="deleteMemberDescription">

        <h2 id="deleteMemberTitle">Delete member?</h2>

        <p class="delete-member-description"
        id="deleteMemberDescription">
            Permanently delete
            <strong id="deleteMemberName"></strong>,
            including their membership history and photo?
            This cannot be undone.
        </p>

        <form method="POST"
            action="monthly_members.php"
            id="deleteMemberForm">

            <input type="hidden"
                name="csrf_token"
                value="<?php echo escapeHtml($_SESSION["csrf_token"]); ?>">

            <input type="hidden"
                name="action"
                value="delete">

            <input type="hidden"
                name="member_id"
                id="deleteMemberId">

            <div class="delete-member-buttons">
                <button type="button"
                        class="cancel-button"
                        data-close
                        autofocus>
                    Cancel
                </button>

                <button type="submit"
                        class="danger-button"
                        id="confirmDeleteMember">
                    Delete member
                </button>
            </div>
        </form>
    </dialog>

    <script src="monthly_members_script.js?v=5"></script>
</body>
</html>