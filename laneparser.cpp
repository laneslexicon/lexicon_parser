#include "laneparser.h"
LaneParser::LaneParser(const QString & dbname) : DomParser() {
  openDb(dbname);
  m_cb = true;
  mapper = im_new();
  //  loadMap("/home/andrewsg/public_html/extjsapps/test02/data/maps/perseus.json");
  //  loadMap("/home/andrewsg/public_html/extjsapps/test02/mappings/js/buckwalter-1.3.js");
  //  entry = new QMap<QString,QString>;
  loadMap("./perseus.js");
  loadMap("./buckwalter-1.4.js");
  nientry = new QMap<QString,ni>;
  m_xalan = getXalan();
  useXalan = true;
}
LaneParser::LaneParser() : DomParser()
{
  mapper = im_new();
  //  loadMap("/home/andrewsg/public_html/extjsapps/test02/data/maps/perseus.json");
  //  loadMap("/home/andrewsg/public_html/extjsapps/test02/mappings/js/buckwalter-1.3.js");
  //  entry = new QMap<QString,QString>;
  loadMap("./perseus.js");
  loadMap("./buckwalter-1.4.js");
  m_cb = true;
  nientry = new QMap<QString,ni>;
  m_xalan = getXalan();
  useXalan = true;
}
LaneParser::~LaneParser() {
  flushRoots();
  nientry->clear();
}
void LaneParser::loadMap(const QString & fileName) {
  QByteArray ba = fileName.toLocal8Bit();
  im_load_map_from_json(mapper,ba.data());
}
void LaneParser::flush() {
  flushRoots();
}
bool LaneParser::parse() {
  qDebug() << Q_FUNC_INFO << m_cb << m_parsePass;
  if (m_cb) {
  m_parsePass++;
  parseInit(m_parsePass);
  loadDOM();  // the first pass do the translate updating DOM in-place
  flush();    // reset anything
  /**
    re-read the DOM building whatever data structure using the converted
    text
  */
  }
  m_parsePass++;
  parseInit(2);
  loadDOM();
  return true;
}

void LaneParser::flushRoots() {
  //  roots.clear();
  xref.clear();
  buckwalter.clear();
  nroots.clear();
}
QString LaneParser::convert(const QString & text) {
  bool ok;
  if (! m_cb) {
    return text;
  }
  QString t;
  t = im_convert_string(mapper,"buckwalter",text,&ok);
  m_bok = ok;
  if (! ok) {
    qWarning() << "Conversion error" << text << t;
  }
  return t;
}
bool LaneParser::execSQL(const QString & dbname,const QString & sqlSource,bool overwrite) {
  QFile file(sqlSource);
  if (!file.open(QFile::ReadOnly | QFile::Text)) {
    std::cerr << "Error: Cannot read file " << qPrintable(sqlSource)
              << ": " << qPrintable(file.errorString())
              << std::endl;
    return false;
  }
  if (overwrite) {
    QFile dbfile(dbname);
    dbfile.remove();
    //    qDebug() << "removed db" << dbname;
  }
  QTextStream in(&file);
  QString sql = in.readAll();
  sql.replace(QRegExp("\n"),"");
  //  qDebug() << QString("[%1]").arg(sql);
  QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE");
  db.setDatabaseName(dbname);
  bool ok = db.open();
  if (ok)
    db = QSqlDatabase::database();

  //  qDebug() << "execSQL, db open" << ok;

  QSqlQuery query;
  QStringList s = sql.split(";");
  for (int i=0;i < s.size();i++) {
    if ( !s[i].isEmpty()) {
      ok = query.exec(s[i]);
      //      qDebug() << "sql" << s[i];
      //      qDebug() << "sqlexec" << ok;
    }
  }
  return ok;
}
bool LaneParser::openDb(const QString & dbname,bool autoCreate) {
  QFile dbfile(dbname);
  bool ok;
  if (! dbfile.exists() && autoCreate) {
    // execSQL opens the database
    ok = execSQL(dbname,"./sql/lanedb.sql",true);
    return ok;
  }
  QSqlDatabase sqldb = QSqlDatabase::addDatabase("QSQLITE");
  sqldb.setDatabaseName(dbname);
  ok = sqldb.open();
  if (ok) {
    db = QSqlDatabase::database();

  }
  qDebug() << Q_FUNC_INFO << "db open" << ok;
  return ok;
}
void LaneParser::traverseXml(QDomNode& node)
{
  QDomNode domNode = node.firstChild();
  QDomElement domElement;
  QDomText domText;
  //  qDebug() << "-------";
  static int level = 0;

  level++;
  while(!(domNode.isNull()))
    {
      // this has to come before the isElement stuff or the dom text
      // will not be converted !!!

      if ((m_parsePass == 1) &&
          domNode.isElement()) {
        domElement = domNode.toElement();
        if   (domElement.tagName() == "entryFree")
        {
          qDebug() << "Setting currentEntryId";
          m_currentEntryId = domElement.attribute("id");
        }
    }
      if (domNode.isText() && (m_parsePass == 1))
        {
          domText = domNode.toText();
          if(!domText.isNull())
            {
              //        qDebug() << __FUNCTION__ << "isText   " << level << QString(level, ' ').toLocal8Bit().constData() << domText.data().toLocal8Bit().constData();
              //
              QDomNode np = domNode.parentNode();
              if (!np.isNull()) {
                QDomElement  pe = np.toElement();
                if (! pe.isNull() &&
                    (pe.hasAttribute("lang") && (pe.attribute("lang") == "ar")))
                  {
                    //              qDebug() << "candidate:" << domText.data().toLocal8Bit().constData();
                    //              emit gotText(domText.data());
                    emit gotTextNode(&domText);
                    QString str  = domText.data();
                    QString c = convert(str);


                    if (! buckwalter.contains(str))
                      buckwalter.insert(str,c); // we are just going to overwrite dups

                    /// for this to work we will have to read up to the the entryFree
                    /// node and get the id, since
                    if (! xref.contains(c)) {
                      QStringList * l = new QStringList;
                      l->append(currentId);
                      qDebug() << "pass" << m_parsePass << "xref insert" << c << "at:" << m_currentEntryId;
                      xref.insert(c,l);
                    }
                    else {
                      QStringList * l = (QStringList *)xref.value(c);
                      if (! l->contains(currentId))
                        l->append(currentId);
                    }
                    domText.setData(c);

                    //              domText.setData("xxxxx");
                  }
              }
              //
            }
        }
      else if (domNode.isElement())
        {
          domElement = domNode.toElement();
          if(!(domElement.isNull()))
            {
              // letter
              if ((domElement.tagName() == "div1") &&
                  (domElement.attribute("type") == "alphabetical letter")) {
                //                qDebug() << "got letter" << domElement.attribute("n");
                //                qDebug() << "convert call 1";
                currentLetter = convert(domElement.attribute("n"));
              }
              // these are the root items
              else if ((domElement.tagName() == "div2") &&
                       (domElement.hasAttribute("type")) &&
                       domElement.attribute("type") == "root")
                {
                  emit(gotRoot(domElement.attribute("n")));
                  qDebug() << "Found root" << domElement.attribute("n");
                  if (! currentRoot.isEmpty()) {
                    //                  roots.insert(currentRoot,entry);
                    if (nroots.contains(currentRoot))  {
                      qDebug() << "warning - duplicate root" << currentRoot;
                    }
                    else {
                      nroots.insert(currentRoot,nientry);
                      nientry = new QMap<QString,ni>;
                    }
                  }
                  //                entry = new QMap<QString,QString>;
                  QString arroot = domElement.attribute("n");
                  if (arroot.startsWith("Quasi")) {
                    //                  qDebug() << "found Quasi" << arroot;
                    arroot = arroot.remove("Quasi");
                  }
                  arroot = arroot.trimmed();
                  //                qDebug() << "convert call 2";
                  currentRoot = convert(arroot);
                  emit(gotRootNode(domNode));
                }
              // this should be entryFree
              else if ((domElement.tagName() == "entryFree") && !  domElement.hasAttributes()) {
                QString str;
                QTextStream stream(&str);
                domElement.save(stream,4);
                qWarning() << "Node without attribs" << str;
              }
              else if ((domElement.tagName() == "entryFree") && !  domElement.hasAttribute("key")) {
                QString str;
                QTextStream stream(&str);
                domElement.save(stream,4);
                qWarning() << "Node without key attrib" << domElement.attribute("id") << str;
              }
              else if ((domElement.tagName() == "entryFree") && domElement.hasAttribute("key")) {
                //          qDebug() << "key" << domElement.attribute("key");
                qDebug() << ">>>>> processing entryFree node";
                QString t;
                QString key = domElement.attribute("key");
                QString mapkey = domElement.attribute("id");
                QString itype;
                QDomNode form;
                QStringList orthforms;
                QDomNodeList forms = domElement.elementsByTagName("form");
                if (forms.count() == 0) {
                  qWarning() << "Node has zero forms" << mapkey << forms.count();
                }
                else {
                  if (forms.count() > 1) {
                  qWarning() << "Node has multiple forms" << mapkey << forms.count();
                  }
                  form = forms.at(0);
                  QDomNodeList f = form.toElement().elementsByTagName("orth");
                  for(int i=0;i < f.size();i++) {
                    QDomElement e = f.at(i).toElement();
                    if (! e.isNull() &&
                        e.hasAttribute("lang") &&
                        (e.attribute("lang") == "ar"))
                      {
                        orthforms << e.firstChild().nodeValue();
                      }
                  }
                }


                QDomNodeList itypes = domElement.elementsByTagName("itype");
                if (! itypes.isEmpty()) {
                  if (itypes.count() > 1) {
                    qWarning() << "Nodes has multiple itypes:" << mapkey << itypes.count();
                  }
                  itype =  itypes.at(0).firstChild().nodeValue();
                  qDebug() << __LINE__ << "node" << mapkey << "itype" << itype << "pass" << m_parsePass;

                }
                if (m_parsePass == 1) {
                  qDebug() << "pass" << m_parsePass << "got node" << mapkey << key;
                  //                  qDebug() << "convert call 3";
                  t = convert(key);
                  domElement.setAttribute("key",t);
                }
                else {
                  qDebug() << __LINE__ << "pass" << m_parsePass << "got node" << mapkey << domElement.attribute("key") << "itype" << itype;
                  currentId = mapkey;
                  ni n;
                  // save the key i.e the actual word n.txt
                  // write the xml to n.xml
                  // save the letter
                  // insert with map key equal nNNNN
                  writeNode(domNode,n.xml);
                  n.txt = key;
                  n.letter = currentLetter;
                  n.itype = itype;
                  qDebug() << "insert entry" << mapkey << n.letter << "text" << n.txt <<"itype" <<  n.itype;
                  if (nientry->contains(mapkey)) {
                    qDebug() << "duplicate entry on" << mapkey;
                  }
                  nientry->insert(mapkey,n);
                  //                entry->insert(mapkey,t);
                  // for each entryFree item emit a signal
                  emit(addedItem(mapkey));
                  emit(gotKeyNode(&domElement));

                }
                qDebug() << "forms" << orthforms;
                  qDebug() << ">>>>> end processing entryFree node";
              }
            }
        }

      traverseXml(domNode);
      domNode = domNode.nextSibling();
    }

  level--;
}
void LaneParser::dumpRoots() {
  qDebug() << "dumping roots";
  QMapIterator<QString, QMap<QString, ni> *> i(nroots);
  while (i.hasNext()) {
    i.next();
    QMap<QString,ni> * e = (QMap<QString,ni> *)i.value();
    QList<QString> keys =  e->keys();
    for(int j=0;j < keys.size();j++) {
      //      qDebug() << keys[j] << e->value(keys[j]);
      ni n = (ni)e->value(keys[j]);
      qDebug() << i.key() << keys[j] << n.txt << n.letter << n.itype;
    }
  }
}
bool LaneParser::updateDb() {
  bool ok;
  bool ret;
  QSqlQuery query;
  int c = 0;
  int total = 0;
  QMapIterator<QString, QMap<QString, ni> *> i(nroots);

  qDebug() << "pass" << m_parsePass << "updateDb, checking" << db.isValid() << db.lastError();
  ok = db.transaction();
  query.prepare("INSERT INTO words (root,word,node,xml,sourcefile,html,letter,node_num,type) "
                "VALUES (:root, :word, :node, :xml, :sourcefile,:html,:letter,:node_num,0)");
  qDebug() << "transaction" << ok;
  QString header = "<TEI.2><text><body><div1>";
  QString footer = "</div1></body></text></TEI.2>";

  while (i.hasNext()) {
    i.next();
    //   qDebug() << i.key();
    QMap<QString,ni> * e = (QMap<QString,ni> *)i.value();
    QList<QString> keys =  e->keys();
    for(int j=0;j < keys.size();j++) {
      //      qDebug() << keys[j] << e->value(keys[j]);
      ni n = (ni)e->value(keys[j]);
      QString xml = n.xml;
      QString html;
      if (useXalan) {
        xml = header + n.xml + footer;
        std::istringstream iss(xml.toStdString());
        std::stringstream ostream;
        m_xalan->transform(iss,"/home/andrewsg/qt5projects/lane/xslt/tei.xsl",ostream);
        QString html = QString::fromStdString(ostream.str());
      }
      //      qDebug() << "u" << n.xml;
      int node_num = -1;
      QString id = keys[j];
      if (id.startsWith("n")) {
        bool ok;
        id.remove(0,1);
        node_num = id.toInt(&ok,10);
        if (! ok )
          node_num = -1;
      }
      query.bindValue(":root", i.key());
      query.bindValue(":word", n.txt);
      query.bindValue(":node", keys[j]);
      query.bindValue(":xml", n.xml);
      query.bindValue(":sourcefile", currentFile);
      query.bindValue(":html", html);
      query.bindValue(":letter", n.letter);
      query.bindValue(":node_num", node_num);
      ok = query.exec();
      c++;
      total++;
      if ( ! ok ) {
        qDebug() << "insert error" << currentFile << keys[j] <<  query.lastError();
        ret = false;
      }
      if (c > 1000) {
        db.commit();
        c = 0;
        db.transaction();
      }
    }
  }
  //  if (c > 0) {
  db.commit();
  //  }
  qDebug() << "update db done" << currentFile << total;
  return ret;
}
void LaneParser::parsingComplete(int pass) {
  if (! currentRoot.isEmpty()) {
    nroots.insert(currentRoot,nientry);
  }
  if (pass == 1)
    updateTranslate();
  if (pass == 2)
    updateXref();
}
bool LaneParser::updateXref() {
  bool ok,ret;
  int c = 0;
  qDebug() << "pass" << m_parsePass << "Xref size:" << xref.size();
  QSqlQuery query;
  ok = db.transaction();
  query.prepare("INSERT INTO xref (word,node,type) "
                "VALUES (:word,:node,0)");
  QMapIterator<QString, QStringList *> i(xref);
  while (i.hasNext()) {
    i.next();
    QStringList * p = (QStringList *)i.value();
    for(int j=0;j < p->size();j++) {
      //      qDebug() << i.key() << *p;
      query.bindValue(":word",i.key());
      query.bindValue(":node",p->at(j));
      ok = query.exec();
      c++;
      if ( ! ok ) {
        qDebug() << query.lastError();
        ret = false;
      }
      if (c > 1000) {
        db.commit();
        c = 0;
        db.transaction();
      }

    }
  }
  db.commit();
  return ret;
}
bool LaneParser::updateTranslate() {
  // update buckwalter
  bool ok,ret;
  int c = 0;
  qDebug() << "pass" << m_parsePass << "Updating buckwalter" << buckwalter.size();
  QSqlQuery buck;
  db.transaction();
  buck.prepare("INSERT INTO buck (win,wout,type)"
               "VALUES (:win, :wout,0)");
  QMapIterator<QString,QString> bi(buckwalter);
  c = 0;
  while(bi.hasNext()) {
    bi.next();
    buck.bindValue(":win",bi.key());
    buck.bindValue(":wout",bi.value());
    ok = buck.exec();
    c++;
    if ( ! ok ) {
      qDebug() << buck.lastError();
      ret = false;
    }
    if (c > 1000) {
      db.commit();
      c = 0;
      db.transaction();
    }
  }
  db.commit();
  return ret;
}
