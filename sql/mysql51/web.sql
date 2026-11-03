-- ============================================================
-- GS/TLBB 初始数据库  [web]
-- MySQL 兼容 | web 账号库(5表: account/h_card/h_cardtype/pay/server)
-- 用法: mysql -uroot -p < web.sql
-- ============================================================
CREATE DATABASE IF NOT EXISTS `web` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
USE `web`;
/*
Navicat MySQL Data Transfer

Source Server         : 106.53.73.97
Source Server Version : 50173
Source Host           : 106.53.73.97:3306
Source Database       : web

Target Server Type    : MYSQL
Target Server Version : 50173
File Encoding         : 65001

Date: 2023-11-17 21:18:57
*/

SET FOREIGN_KEY_CHECKS=0;

-- ----------------------------
-- Table structure for account
-- ----------------------------
DROP TABLE IF EXISTS `account`;
CREATE TABLE `account` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL,
  `password` char(32) NOT NULL,
  `question` varchar(64) DEFAULT NULL,
  `answer` varchar(64) DEFAULT NULL,
  `email` varchar(64) DEFAULT NULL,
  `qq` varchar(16) DEFAULT NULL,
  `tel` varchar(16) DEFAULT NULL,
  `id_type` enum('IdCard') DEFAULT 'IdCard',
  `id_card` varchar(32) DEFAULT NULL,
  `point` int(11) NOT NULL DEFAULT '0',
  `is_online` smallint(1) unsigned NOT NULL DEFAULT '0',
  `is_lock` smallint(1) unsigned NOT NULL DEFAULT '0',
  `mibaocard` text NOT NULL,
  `ctime` int(1) DEFAULT '0',
  `vtime` int(1) DEFAULT '0',
  PRIMARY KEY (`id`,`name`) USING BTREE,
  UNIQUE KEY `id` (`id`) USING BTREE,
  UNIQUE KEY `name` (`name`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=23 DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

-- ----------------------------
-- Records of account
-- ----------------------------

-- ----------------------------
-- Table structure for h_card
-- ----------------------------
DROP TABLE IF EXISTS `h_card`;
CREATE TABLE `h_card` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `typeid` int(11) NOT NULL,
  `logicid` int(11) DEFAULT NULL,
  `cardid` char(64) NOT NULL,
  `used` smallint(6) DEFAULT NULL,
  `used_data` char(128) NOT NULL,
  `tips` char(128) NOT NULL,
  `validity` int(11) DEFAULT NULL,
  `validity_t` int(11) DEFAULT NULL,
  `ex_data` int(11) DEFAULT NULL,
  `create_time` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

-- ----------------------------
-- Records of h_card
-- ----------------------------

-- ----------------------------
-- Table structure for h_cardtype
-- ----------------------------
DROP TABLE IF EXISTS `h_cardtype`;
CREATE TABLE `h_cardtype` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

-- ----------------------------
-- Records of h_cardtype
-- ----------------------------

-- ----------------------------
-- Table structure for pay
-- ----------------------------
DROP TABLE IF EXISTS `pay`;
CREATE TABLE `pay` (
  `trade_no` varchar(20) NOT NULL,
  `channel` varchar(10) DEFAULT NULL,
  `server_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `fee` int(11) NOT NULL,
  `status` tinyint(4) NOT NULL,
  `create_time` datetime NOT NULL,
  `pay_time` datetime DEFAULT NULL,
  PRIMARY KEY (`trade_no`) USING BTREE,
  KEY `trade_no` (`trade_no`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

-- ----------------------------
-- Records of pay
-- ----------------------------

-- ----------------------------
-- Table structure for server
-- ----------------------------
DROP TABLE IF EXISTS `server`;
CREATE TABLE `server` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL,
  `host` char(60) NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

-- ----------------------------
-- Records of server
-- ----------------------------
