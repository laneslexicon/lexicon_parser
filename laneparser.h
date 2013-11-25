#ifndef __LANEPARSER_H__
#define __LANEPARSER_H__
#include "domparser.h"
#include "inputmapper.h"
#include "lanesettings.h"
#include <QDateTime>
#include <QMap>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlDriver>
#include <QRegExp>
#include <QTextStream>
#include <QFileInfo>
#include <sstream>
#include "xsltsupport.h"
typedef struct {
  QString xml;
  QString txt;
  QString letter;
  QString itype;
} ni;
class LaneParser : public DomParser {
  Q_OBJECT
 public:
  LaneParser();
  ~LaneParser();
  LaneParser(const QString & dbname);
  void loadMap(const QString &); // load map from filename
  bool execSQL(const QString & dbname,const QString & sqlSource,bool overwrite=false);
  bool openDb(const QString & dbname,bool autoCreate = true);
  void setConvertBuckwalter(bool v) {
    m_cb = v;
  }
  void setUpdateDb(bool v) {
    m_updateDb = v;
  }
  void setSQL(const QString & source) {
    m_sqlSource = source;
  }
  void setInitDb(bool v) {
    m_initDb = v;
  }
  void dumpRoots();
  //  bool updateDb();
  bool updateDb();
  bool updateXref();
  bool updateTranslate();
   void flushRoots();

   void setXalan(bool v) {
     useXalan = v;
   }
   void setXsl(const QString & fileName) {
     m_teiXSL = fileName;
   }
   bool parse();
   QString convert(const QString &,int callId=0);
 private:
   QString m_teiXSL;
   QString m_currentEntryId;
   QDomNode m_currentNode;
   bool m_bok;    // whether or not the last call to im_convert_string work
   bool m_cb;     // convert buckwalter
   bool m_initDb;
   QString m_sqlSource;
   QString m_dbName;
   bool useXalan;
   XalanTransformer * m_xalan;
   LaneSettings m_settings;
  InputMapper * mapper;
  QSqlDatabase m_db;    // sqlite3 database
  QTextStream m_buckLog;
  QFile m_buckLogFile;
  int m_buckErrors;

  QTextStream m_sqlLog;
  QFile m_SqlLogFile;
  /// for debugging to mimic database inserts
  int m_rootId;
  int m_itypeId;
  int m_entryId;
  int m_xrefId;

  int m_writeCount;
  int m_lastId;
  int m_dbRootId;       // the sqlite id key of the current root

  bool m_updateDb;
  QSqlQuery m_rootQuery;
  QSqlQuery m_itypeQuery;
  QSqlQuery m_entryQuery;
  QSqlQuery m_xrefQuery;

  void setupSQL();
  void openLogs();
  bool writeXref(const QString & word,const QString & node,bool update=true);
  bool writeRoot(const QString & root,const QString & letter,bool update=true);
  bool writeItype(const QString & itype,const QString nodeId,const QString & word,const QString & xml,bool update=true);
  bool writeEntry(const QString & nodeId,const QString & word,const QString xml,bool update=true);
  QMap<QString,QString> buckwalter;
  //  QMap<QString, QMap<QString,QString> *> roots;
  //  QMap<QString,QString> * entry;
  QMap<QString, QMap<QString,ni> *> nroots;
  QMap<QString,ni> * nientry;
  QMap<QString,QStringList *> xref;
  QString currentId;   // the current nodeId (nNNNNN)
  QString currentRoot;
  QString currentLetter;
  virtual void traverseXml(QDomNode &);
  virtual void parsingComplete(int);
  virtual void flush();
 signals:
  void gotRootNode(const QDomNode &);
  void gotRoot(QString);
  void addedItem(const QString &);
};
#endif
