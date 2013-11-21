#ifndef _LANESETTINGS_
#define _LANESETTINGS_
#include <QObject>
#include <QString>
#include <QMap>
#include <QSettings>
#include <QDebug>
#include <QStringList>
class LaneSettings : public QObject {
  Q_OBJECT

 public:
  LaneSettings();
  QString m_org;
  QString m_app;
  QString m_dbname;
  QString m_tei_xsl;
  QString m_entry_css_file;
  QString m_entry_css;

  int     m_xref_cc;
  int     m_words_cc;
  int     m_buck_cc;
  QMap<QString,QString> m_maps;
  QString m_initSQL;
  void readSettings();
  void writeSettings();
};
#endif
