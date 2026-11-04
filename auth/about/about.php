<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>About Us | PeakGym Management</title>

    <link rel="icon" type="image/png" href="../../assets/favicon.png">
    <link rel="stylesheet" href="about_style.css?v=1">
</head>
<body>

    <!-- NAVIGATION -->
    <nav aria-label="Main navigation">
        <a href="login.php" class="logo">
            <img
                src="../../assets/logo_peak.png"
                alt="Peak Gym logo"
                width="60"
                height="60"
            >
            <span>PEAKGYM</span>
        </a>

        <ul>
            <li>
                <a href="about.php" class="active" aria-current="page">
                    About
                </a>
            </li>
        </ul>

        <a href="login.php" class="member-btn">Log in</a>
    </nav>

    <main>
        <!-- ABOUT HEADER -->
        <div class="header-section">
            <div class="tagline">OUR STORY</div>

            <h1>About PeakGym</h1>

            <p class="about-intro">
                Learn more about our gym and what makes us different.
            </p>
        </div>

        <!-- OUR STORY -->
        <div class="about-content">
            <div class="about-text">
                <p>
                    PeakGym was founded in 1997, with a simple goal —
                    to help people in our community get fit and healthy.
                    We started small but always focused on giving the
                    best service to our members.
                </p>

                <p>
                    In 2010 and 2024, we renovated our gym to make it
                    bigger and better. We added new equipment and
                    improved our facilities to give our members the
                    best workout experience.
                </p>

                <p>
                    Today, PeakGym continues to grow and serve the
                    people of Cabadbaran City. We are committed to
                    helping everyone reach their fitness goals,
                    no matter their level.
                </p>
            </div>
        </div>

        <!-- VALUES -->
        <section class="values-section" aria-labelledby="values-heading">
            <div class="values-inner">
                <div class="values-top">
                    <div class="values-small">OUR VALUES</div>
                    <h2 id="values-heading">What We Stand For</h2>
                </div>

                <div class="values-grid">
                    <div class="value-card">
                        <div class="value-icon">
                            <svg
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                stroke-width="2"
                                aria-hidden="true"
                            >
                                <circle cx="12" cy="12" r="10"></circle>
                                <circle cx="12" cy="12" r="6"></circle>
                                <circle cx="12" cy="12" r="2"></circle>
                            </svg>
                        </div>

                        <h3>Mission-Driven</h3>
                        <p>
                            Every program has a clear goal —
                            to help you improve yourself.
                        </p>
                    </div>

                    <div class="value-card">
                        <div class="value-icon">
                            <svg
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                stroke-width="2"
                                aria-hidden="true"
                            >
                                <path
                                    d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"
                                ></path>
                            </svg>
                        </div>

                        <h3>Excellence</h3>
                        <p>
                            We give our best in training and
                            service for every member.
                        </p>
                    </div>

                    <div class="value-card">
                        <div class="value-icon">
                            <svg
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                stroke-width="2"
                                aria-hidden="true"
                            >
                                <path
                                    d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"
                                ></path>
                                <circle cx="9" cy="7" r="4"></circle>
                                <path
                                    d="M23 21v-2a4 4 0 0 0-3-3.87"
                                ></path>
                                <path
                                    d="M16 3.13a4 4 0 0 1 0 7.75"
                                ></path>
                            </svg>
                        </div>

                        <h3>Community</h3>
                        <p>
                            We build connections that motivate
                            and inspire every member.
                        </p>
                    </div>

                    <div class="value-card">
                        <div class="value-icon">
                            <svg
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                stroke-width="2"
                                aria-hidden="true"
                            >
                                <path
                                    d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"
                                ></path>
                            </svg>
                        </div>

                        <h3>Innovation</h3>
                        <p>
                            We use modern training methods and
                            equipment to help you get better results.
                        </p>
                    </div>
                </div>
            </div>
        </section>

        <!-- TEAM -->
        <section class="staff-section" aria-labelledby="team-heading">
            <div class="staff-header">
                <div class="tagline">OUR TEAM</div>

                <h2 id="team-heading">Coach &amp; Staff PeakGym</h2>

                <p class="staff-desc">
                    Meet the people who make PeakGym great.
                </p>
            </div>

            <div class="staff-grid">
                <div class="staff-card">
                    <div class="staff-img">
                        <img
                            src="../assets/images/jaysondady(2).png"
                            alt="Jayson Dady"
                            loading="lazy"
                        >

                        <div class="staff-caption">
                            <div class="staff-name">Jayson Dady</div>
                            <div class="staff-role">Coach</div>
                        </div>
                    </div>
                </div>

                <div class="staff-card">
                    <div class="staff-img">
                        <img
                            src="../../assets/stevenp.png"
                            alt="Steven Payapaya"
                            loading="lazy"
                        >

                        <div class="staff-caption">
                            <div class="staff-name">Steven Payapaya</div>
                            <div class="staff-role">Front Desk</div>
                        </div>
                    </div>
                </div>
            </div>
        </section>
    </main>

    <!-- FOOTER -->
    <footer>
        <div class="copyright">
            &copy; <?php echo date('Y'); ?> PeakGym Fitness.
            All rights reserved.
        </div>

        <div class="design-tag">
            Designed with passion for fitness
        </div>
    </footer>

</body>
</html>