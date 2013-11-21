#ifndef __DOMPARSER_H__
#define __DOMPARSER_H__
#include <QFile>
#include <QDomElement>
#include <QString>
#include <QDomDocument>
#include <QDomText>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <iostream>
#include <QTextStream>
class DomParser : public QObject {
  Q_OBJECT
 public:
  DomParser();
  bool readFile(const QString &,bool);
  bool saveFile(const QString &);
  bool writeNode(const QDomNode &,const QString &);
  bool writeNode(const QDomNode &,QString &);
  bool loadDOM();
  bool parse();
 protected:
  int m_parsePass;
  QDomDocument doc;
  QString currentFile;
  void parseElement(QDomNode &);
  virtual void parseInit(int);
  virtual void traverseXml(QDomNode &);
  virtual void parsingComplete(int);
  virtual void flush();
 signals:
  void gotText(const QString &);
  void gotTextNode(QDomText *);
  void gotKey(const QString &);
  void gotKeyNode(QDomElement *);
  void parseComplete(int);
};
#endif
