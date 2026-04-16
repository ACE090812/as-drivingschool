-- ──────────────────────────────────────────────────────────────────────────────
--  DVLA — Database Setup
--  Run this file once, or let the server auto-execute it on first start.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `dvla_licences` (
    `id`               INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`        VARCHAR(50)  NOT NULL,
    `licence_type`     VARCHAR(20)  NOT NULL DEFAULT 'none',
    -- 'none' | 'provisional' | 'full' | 'suspended'
    `theory_passed`    TINYINT(1)   NOT NULL DEFAULT 0,
    `practical_passed` TINYINT(1)   NOT NULL DEFAULT 0,
    `issue_date`       VARCHAR(20)  DEFAULT NULL,
    `penalty_points`   INT(11)      NOT NULL DEFAULT 0,
    `suspended`        TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `dvla_theory_tests` (
    `id`          INT(11)     NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50) NOT NULL,
    `score`       INT(11)     NOT NULL,
    `max_score`   INT(11)     NOT NULL DEFAULT 15,
    `passed`      TINYINT(1)  NOT NULL,
    `date`        VARCHAR(30) NOT NULL,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `dvla_practical_tests` (
    `id`           INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`    VARCHAR(50)  NOT NULL,
    `centre`       VARCHAR(100) DEFAULT NULL,
    `minor_faults` INT(11)      NOT NULL DEFAULT 0,
    `major_faults` INT(11)      NOT NULL DEFAULT 0,
    `passed`       TINYINT(1)   NOT NULL,
    `examiner`     VARCHAR(100) DEFAULT NULL,
    `date`         VARCHAR(30)  NOT NULL,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `dvla_mot_tests` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50)  NOT NULL,
    `plate`       VARCHAR(20)  NOT NULL,
    `passed`      TINYINT(1)   NOT NULL,
    `inspector`   VARCHAR(100) DEFAULT NULL,
    `notes`       TEXT         DEFAULT NULL,
    `expiry_date` VARCHAR(30)  DEFAULT NULL,
    `date`        VARCHAR(30)  NOT NULL,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `dvla_penalty_points` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`  VARCHAR(50)  NOT NULL,
    `offence`    VARCHAR(200) NOT NULL,
    `points`     INT(11)      NOT NULL,
    `issued_by`  VARCHAR(100) DEFAULT NULL,
    `date`       VARCHAR(30)  NOT NULL,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
