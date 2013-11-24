#ifndef __LANEPARSER_H__
#define __LANEPARSER_H__
#include "domparser.h"
#include "inputmapper.h"
#include "lanesettings.h"
#include <QMap>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlDriver>
#include <QRegExp>
#include <QTextStream>
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
   bool useXalan;
   XalanTransformer * m_xalan;
   LaneSettings m_settings;
  InputMapper * mapper;
  QSqlDatabase db;
  QTextStream m_buckLog;
  QFile m_buckLogFile;
  int m_buckErrors;

  QTextStream m_sqlLog;
  QFile m_SqlLogFile;

  int m_rootId;
  int m_itypeId;
  int m_wordId;
  QMap<QString,QString> buckwalter;
  //  QMap<QString, QMap<QString,QString> *> roots;
  //  QMap<QString,QString> * entry;
  QMap<QString, QMap<QString,ni> *> nroots;
  QMap<QString,ni> * nientry;
  QMap<QString,QStringList *> xref;
  QString currentId;
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
