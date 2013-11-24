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
  m_buckErrors = 0;
  m_buckLogFile.setFileName("conversion.log");
  if (m_buckLogFile.open(QFile::WriteOnly | QFile::Truncate)) {
    m_buckLog.setDevice(&m_buckLogFile);
    //    out << "Result: " << qSetFieldWidth(10) << left << 3.14 << 2.7;
    // writes "Result: 3.14      2.7       "
  }
  m_SqlLogFile.setFileName("sql.log");
  if (m_SqlLogFile.open(QFile::WriteOnly | QFile::Truncate)) {
    m_sqlLog.setDevice(&m_SqlLogFile);
    //    out << "Result: " << qSetFieldWidth(10) << left << 3.14 << 2.7;
    // writes "Result: 3.14      2.7       "
  }
  m_rootId = 0;
  m_itypeId = 0;
  m_wordId = 0;

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
  m_buckErrors = 0;
  m_buckLogFile.setFileName("conversion.log");
  if (m_buckLogFile.open(QFile::WriteOnly | QFile::Truncate)) {
    m_buckLog.setDevice(&m_buckLogFile);
    //    out << "Result: " << qSetFieldWidth(10) << left << 3.14 << 2.7;
    // writes "Result: 3.14      2.7       "
  }
  m_SqlLogFile.setFileName("sql.log");
  if (m_SqlLogFile.open(QFile::WriteOnly | QFile::Truncate)) {
    m_sqlLog.setDevice(&m_SqlLogFile);
    //    out << "Result: " << qSetFieldWidth(10) << left << 3.14 << 2.7;
    // writes "Result: 3.14      2.7       "
  }

  m_rootId = 0;
  m_itypeId = 0;
  m_wordId = 0;

}
LaneParser::~LaneParser() {
  flushRoots();
  nientry->clear();
  m_buckLog << QString("File %1, errors %2").arg(currentFile).arg(m_buckErrors);
  m_buckLog.flush();
  m_buckLogFile.close();

  m_sqlLog.flush();
  m_SqlLogFile.close();
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

  updateXref();
  updateTranslate();
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
QString LaneParser::convert(const QString & text,int callId) {
  bool ok;
  if (! m_cb) {
    return text;
  }
  QString t;
  t = im_convert_string(mapper,"buckwalter",text,&ok);
  m_bok = ok;
  if (! ok) {
    m_buckErrors++;
    m_buckLog << QString("conversion error %1 at node: %2\n").arg(callId).arg(m_currentEntryId);
    m_buckLog << QString("In: [%1], at pos %2,[char= %3]\n").arg(text).arg(mapper->m_errorIndex).arg(mapper->m_errorChar);
    QString str;
    QTextStream stream(&str);
    m_currentNode.toElement().save(stream,4);
    m_buckLog << str << "\n";
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
                    QString c = convert(str,1);


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
          m_currentNode = domNode;
          domElement = domNode.toElement();
          if(!(domElement.isNull()))
            {
              // letter
              if ((domElement.tagName() == "div1") &&
                  (domElement.attribute("type") == "alphabetical letter")) {
                //                qDebug() << "got letter" << domElement.attribute("n");
                //                qDebug() << "convert call 1";
                currentLetter = convert(domElement.attribute("n"),2);
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
                  currentRoot = convert(arroot,3);
                  emit(gotRootNode(domNode));
                  /// create root table entry
                  if (m_parsePass == 2) {
                    m_sqlLog << QString("insert into root values(%1,\"%2\",\"%3\")\n").arg(m_rootId)
                      .arg(currentRoot)
                      .arg(currentLetter);
                    m_rootId++;
                  }
                }
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
                // QDomNode form;
                QStringList orthforms;
                /*
                  get the immediate form child and iterate through all its
                  orth elements
                */
                QDomElement form = domElement.firstChildElement("form");
                if (! form.isNull()) {
                  QDomNodeList f = form.elementsByTagName("orth");
                  for(int i=0;i < f.size();i++) {
                    QDomElement e = f.at(i).toElement();
                    /**
                     * the xml contains entries like this:
                     <form>
                        <orth orig="" extent="full" lang="ar">jaAbapN</orth>
                        <orth extent="full" lang="ar">jAb</orth>
                        <orth extent="full" lang="ar">jAbh</orth>
                        <orth extent="full" lang="ar">jAbp</orth>
                      </form>                     *
                     *
                     *
                     * the first entry is in Lane, but I don't know where the others
                     * have come from
                     *
                     */
                    if (! e.isNull() &&
                        (e.hasAttribute("orig")) &&
                        (e.attribute("orig") == "") &&   // exclude where orig="full"
                        e.hasAttribute("lang") &&
                        (e.attribute("lang") == "ar"))
                      {
                        QString str = e.firstChild().nodeValue();
                        if (! orthforms.contains(str)) {
                          orthforms << str;
                        }
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
                  t = convert(key,4);
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

  updateXref();
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
