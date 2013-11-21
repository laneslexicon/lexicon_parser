#include "lanesettings.h"
LaneSettings::LaneSettings() {
  m_org = "Gabanjo";
  m_app = "Lane Lexicon";
}
void LaneSettings::readSettings() {
  QSettings settings(m_org, m_app);

  settings.beginGroup("Database");
  m_dbname = settings.value("dbname", QString("full.sqlite")).toString();
  qDebug() << "readsettings" << m_dbname;
  m_xref_cc = settings.value("xref_commit_count",200).toInt();
  m_words_cc = settings.value("words_commit_count",1000).toInt();
  m_buck_cc = settings.value("buck_commit_count",1000).toInt();
  m_initSQL = settings.value("SQL",QString("/home/andrewsg/qt5projects/lane/sql/lanedb.sql")).toString();
  settings.endGroup();

  settings.beginGroup("Xalan");
  m_tei_xsl = settings.value("TEI","/home/andrewsg/qt5projects/lane/xslt/tei.xsl").toString();
  settings.endGroup();

  settings.beginGroup("Maps");
  QStringList maps = settings.childKeys();
  qDebug() << "maps" << maps;
  for(int i=0;i < maps.size();i++) {
    m_maps.insert(maps[i],settings.value(maps[i]).toString());
  }
  if (maps.size() == 0) {
    m_maps.insert("arabic","/home/andrewsg/public_html/extjsapps/test02/mappings/js/buckwalter-1.3.js");
    m_maps.insert("greek","/home/andrewsg/public_html/extjsapps/test02/data/maps/perseus.json");

  }


  settings.endGroup();

  settings.beginGroup("Appearance");
  m_entry_css_file = settings.value("lexicon_entry_css","./css/lexicon_entry.css").toString();


  settings.endGroup();
}
void LaneSettings::writeSettings() {
  qDebug() << "writing settings";
  QSettings settings(m_org, m_app);

  settings.setValue("Database/dbname",m_dbname);
  settings.setValue("Database/xref_commit_count",m_xref_cc);
  settings.setValue("Database/words_commit_count",m_words_cc);
  settings.setValue("Database/buck_commit_count",m_buck_cc);
  settings.setValue("Database/SQL",m_initSQL);
  settings.setValue("Xalan/TEI",m_tei_xsl);

  settings.setValue("Appearance/lexicon_entry_css",m_entry_css_file);


  QMapIterator<QString,QString> i(m_maps);
  while(i.hasNext()) {
    i.next();
    settings.setValue(QString("Maps/%1").arg(i.key()),i.value());
  }
  settings.sync();
}
