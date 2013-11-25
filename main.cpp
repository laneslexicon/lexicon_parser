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
#include "task.h"

//#include "main.moc"

int main(int argc, char *argv[])
{
  QCoreApplication a(argc,argv);
  //  Task * task = new Task(&a);
  //Task task(&a);
  QStringList cmdargs = QCoreApplication::arguments();
  SqlTask task(&a);
  // This will cause the application to exit when
  // the task signals finished.
  QObject::connect(&task, SIGNAL(finished()), &a, SLOT(quit()));

  // This will run the task from the application event loop.
  QMap<QString,int> optmap;
  bool parseFile = false;
  bool execSql = false;
  bool doTimings = false;
  bool doSort = false;
  bool doXalan = false;
  bool noDbUpdate = false;
  bool noTransform = false;
  bool dumpRoots = false;
  bool doAll = false;
  bool doLaneVolume = false;
  bool doBuckwalter = false;
  bool initDb = false;
  int ix;
  optmap.insert("-init-db",0);
  optmap.insert("-d",1);
  optmap.insert("-s",1);
  optmap.insert("-db",1);
  optmap.insert("-sql",1);
  optmap.insert("-v",0);
  optmap.insert("-timer",0);
  optmap.insert("-sort",0);
  optmap.insert("-xalan",0);
  optmap.insert("-no-update",0);
  optmap.insert("-no-transform",0);
  optmap.insert("-dump",0);
  optmap.insert("-salmone",0);
  optmap.insert("-lane",0);
  optmap.insert("-vol",1);
  optmap.insert("-quran",0);
  optmap.insert("-b",0);
  while( ! cmdargs.isEmpty()) {
    QString opt = cmdargs.takeFirst();
    //    qDebug() << "arg" << opt;
    if (optmap.contains(opt)) {
      int argcount = optmap.value(opt);
      QStringList optargs;
      for(int i=0;i < argcount;i++) {
        optargs << cmdargs.takeFirst();
      }
      if (opt == "-init-db") {
        initDb = true;
      }
      if (opt == "-b") {
        doBuckwalter = true;
      }
      if (opt == "-d") {
        qDebug() << "directory" << optargs[0];
        task.dirName = optargs[0];
      }
      if (opt == "-s") {
        qDebug() << "source" << optargs[0];
        task.sourceName = optargs[0];
      }
      if (opt == "-db") {
        qDebug() << "db" << optargs[0];
        task.dbName = optargs[0];
      }
      if (opt == "-v") {
        qDebug() << "verbose set";
      }
      if (opt == "-timer") {
        doTimings = true;
      }
      if (opt == "-sql") {
        task.sqlSource = optargs[0];
        execSql = true;
      }
      if (opt == "-sort") {
        doSort = true;
      }
      if (opt == "-xalan") {
        doXalan = true;
      }
      if (opt == "-all") {
        doAll = true;
      }
      if (opt == "-vol") {
        doLaneVolume = true;
        task.sourceName = optargs[0];
      }
      if (opt == "-no-update") {
        noDbUpdate = true;
      }
      if (opt == "-no-transform") {
        noTransform = true;
      }
      if (opt == "-dump") {
        dumpRoots = true;
      }
    }
  }
  task.initDb = initDb;
  task.updateDb = ! noDbUpdate;
  task.noTransform = noTransform;
  task.dumpRoots = dumpRoots;
  task.convert = doBuckwalter;
  if (doAll)
    QTimer::singleShot(0, &task, SLOT(parseLane()));
  else if (doLaneVolume)
      QTimer::singleShot(0, &task, SLOT(parseFile()));
  else if (execSql)
    QTimer::singleShot(0, &task, SLOT(execSQL()));
  else if (doTimings)
    QTimer::singleShot(0, &task, SLOT(timings()));
  else if (doSort)
    QTimer::singleShot(0, &task, SLOT(sort()));
  else if (doXalan)
    QTimer::singleShot(0, &task, SLOT(xalan()));
  else
    QTimer::singleShot(0, &task, SLOT(run()));

  return a.exec();
}
