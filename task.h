#ifndef __TASK_H__
#define __TASK_H__
#include <QCoreApplication>
#include <QDebug>
#include <QTimer>
#include <QTime>
#include <QSettings>
#include <QStringList>
#include <QJsonDocument>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QFile>
#include <iostream>
#include <string>
#include <QDir>
#include <QDirIterator>

#include <sstream>
#include "laneparser.h"
#include "lanesettings.h"
#include "xsltsupport.h"
class SqlTask : public QObject
{
  Q_OBJECT
public:
  SqlTask(QCoreApplication * parent = 0) : QObject(parent) {
    m_settings.readSettings();
    dbName = "lane.sqlite";
  }
  // these are for read settings
  LaneSettings m_settings;
  QString dirName;
  QString sourceName;
  QString dbName;
  QString sqlSource;
  bool dbUpdate;
  bool noTransform;
  bool dumpRoots;
  bool convert;     // convert buckwalter to arabic
public slots:
  void run();
  void parseLane();
  void parseFile();
  void execSQL();
  void timings();
  void sort();
  void xalan();
  void got_root(const QString &);
signals:
  void finished();
private:
  LaneParser * parser;
  QSqlDatabase db;
};
#endif
