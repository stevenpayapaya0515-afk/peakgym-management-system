<?php
$host =  "localhost";
$username = "root";
$password = "";
$dbname = "security_1";

$conn = mysqli_connect($host, $username, $password, $dbname);

if (!$conn) {
    die("Connection failed: " . mysqli_connect_error());
}

date_default_timezone_set("Asia/Manila");

/* LOGIN AND SIGN UP */
if($_SERVER["REQUEST_METHOD"] == "POST") {

    $action = $_POST["action"] ?? "login";

    /* LOGIN */
    if ($action == "login") {

        $loginUsername = $_POST["username"];
        $loginPassword = $_POST["password"];

        // Find the account
        $sql = "SELECT * FROM users 
            WHERE username = '$loginUsername'";

        $result = mysqli_query($conn, $sql);

        if (mysqli_num_rows($result) > 0) {

            $user = mysqli_fetch_assoc($result);


            // Check the password
            if ($user["password"] == $loginPassword) {

                // Correct password - reset failed attempts
                $reset = "UPDATE users
                        SET failed_attempts = 0,
                            locked_until = NULL
                        WHERE username = '$loginUsername'";

                mysqli_query($conn, $reset);

                header("Location: login.php?login=success");
                exit();

            } else {

                // Wrong password - add one failed attempt
                $failedAttempts = $user["failed_attempts"] + 1;

                // Lock after 5 failed attempts
                $update = "UPDATE users
                        SET failed_attempts = $failedAttempts
                        WHERE username = '$loginUsername'";

                mysqli_query($conn, $update);

                http_response_code(401);
                echo "Invalid username or password.";
                exit();
            }
        } else {

            http_response_code(401);
            echo "Invalid username or password.";
            exit();
        }
    }
}
?>





<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PeakGym Management</title>
    <link rel="stylesheet" href="style.css">
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

                <div class="auth-nav">
                    <a href="login.php" class="nav-login active">Log In</a>
                    <a href="signup.php" class="nav-login">Sign Up</a>
                </div>
            </header>


            <!-- AUTH SECTION -->
            <section class="auth">

                <!-- LEFT CONTENT -->
                <div class="intro">
                    <p class="label">PEAKGYM MANAGEMENT</p>

                    <h1>
                        Manage your gym.<br>
                        <span>Keep it moving.</span>
                    </h1>

                    <p class="description">
                        Your space for managing members, attendance, and everyday gym operations.
                    </p>
                </div>


                <!-- RIGHT AUTH CARD -->
                <div class="card">

                    <!-- LOGIN FORM -->
                    <div class="login">
                        <p class="label">WELCOME BACK</p>
                        <h2>Log in</h2>
                        <p class="subtext">Access your PeakGym management account.</p>

                        <form method="POST" action="login.php" id="loginForm">
                            <input type="hidden" name="action" value="login">

                            <label>Username or Email</label>
                            <input type="text" id="loginEmail" name="username">

                            <label>Password</label>
                            <div class="password-wrapper">
                                <input type="password" id="loginPassword" name="password">
                                <button type="button" id="togglePassword" class="toggle-password" aria-label="Show password">
                                        <svg viewBox="0 0 24 24" aria-hidden="true">
                                            <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"></path>
                                            <circle cx="12" cy="12" r="2.5"></circle>
                                        </svg>
                                </button>
                            </div>

                            <div class="options">
                                <label>
                                    <input type="checkbox">
                                    Remember me
                                </label>

                                <a href="#">Forgot password?</a>
                            </div>

                            <p class="error-message" id="loginError"></p>

                            <button type="submit" id="loginSubmit">LOG IN</button>
                        </form>

                        <p class="switch">
                            Need an account? Contact your gym administrator.
                        </p>
                    </div>
            </section>

        </main>

        <script src="script.js"></script>
    </body>
</html>