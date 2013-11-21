#include "task.h"
void SqlTask::got_root(const QString & id) {
  //  qDebug() << "got" << id;
}
void SqlTask::xalan() {
  XalanTransformer * x = getXalan();
  /*
    xalanc_1_10::XSLTInputSource xmlIn("../tmp/test.xml");
    xalanc_1_10::XSLTInputSource   xslIn("../xslt/tei.xsl");
    xalanc_1_10::XSLTResultTarget xmlOut("foo-out.xml");
  */
  QFile file("../tmp/test.xml");
  if (!file.open(QFile::ReadOnly | QFile::Text)) {
    std::cerr << "Error: Cannot read file " << qPrintable(sqlSource)
              << ": " << qPrintable(file.errorString())
              << std::endl;
  }
  QString xml;
  QTextStream infile(&file);
  while(! infile.atEnd()) {
    xml += infile.readLine();
  }

  std::istringstream iss(xml.toStdString());
  //  std::cout << xml.toStdString();
  std::string ss;
  //  iss >> ss;
  std::cout  << ss;
  std::stringstream ostream;
  int theResult =
    //    x.transform("../tmp/test.xml","../xslt/tei.xsl",xmlOut)
    // x.transform("../tmp/test.xml","../xslt/tei.xsl",ostream);
    x->transform(iss,"../xslt/tei.xsl",ostream);
  // x.transform(xml.toStdString(),"../xslt/tei.xsl",ostream);
  //   XalanTransformer::terminate();
  //  XMLPlatformUtils::Terminate();
  std::cout << ostream.str();
  QString t;
  t = QString::fromStdString(ostream.str());
  emit(finished());
}
void SqlTask::sort() {
  QFile file("../roots.txt");
  if (!file.open(QFile::ReadOnly | QFile::Text)) {
    std::cerr << "Error: Cannot read file " << qPrintable(sqlSource)
              << ": " << qPrintable(file.errorString())
              << std::endl;
    emit(finished());
    return;
  }
  QStringList roots;
  QTextStream in(&file);
  while(! in.atEnd()) {
    roots << in.readLine();
  }
  roots.sort();
  for(int i=0;i < roots.size();i++) {
    std::cout << qPrintable(roots[i]) << std::endl;
  }
  emit(finished());
}
void SqlTask::timings() {
  QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE");
  db.setDatabaseName(dbName);
  bool ok = db.open();
  qDebug() << "db open" << ok;
  if (! ok)
    return;
  db = QSqlDatabase::database();
  QTime st;
  st.start();
  QSqlQuery query("SELECT distinct root FROM words");
  QStringList roots;
  QList<int> key;
  while (query.next()) {
    roots <<  query.value(0).toString();
  }
  qDebug() << "root count" << roots.size() << st.elapsed();
  roots.sort();
  int rc = roots.size();
  int wc = 0;
  //    rc = 200;
  for(int i=0; i < rc;i++) {
    QSqlQuery children(QString("select word,id,node,sourcefile from words where root = \"%1\"").arg(roots[i]));
    while(children.next()) {
      //        qDebug() << children.value(0).toString() << children.value(1).toString() << \
      //          children.value(2).toString() << children.value(3).toString();
      wc++;
    }
  }
  qDebug() << "wordcount" << wc << st.elapsed();
  db.close();
  emit(finished());

}
void SqlTask::parseFile() {
  qDebug() << "parsing" << sourceName;
  if (sourceName.isEmpty() ||
      dbName.isEmpty()) {
    qDebug() << "Missing params" << sourceName << dbName;
    emit(finished());
    return;
  }
  parser = new LaneParser(dbName);
  parser->setXalan(! noTransform );
  if (parser->readFile(sourceName,false)) {
    parser->parse();
    if (dbUpdate)
      parser->updateDb();
    if (dumpRoots)
      parser->dumpRoots();
  }
  delete parser;
  qDebug() << "parsing finished";
  emit(finished());
}
void SqlTask::execSQL() {
  qDebug() << "execSQL" << dbName << sqlSource;
  if (sqlSource.isEmpty() ||
      dbName.isEmpty()
      )
    emit(finished());

  parser = new LaneParser;
  parser->execSQL(dbName,sqlSource,true);
  emit(finished());
}
void SqlTask::parseLane() {
  qDebug() << Q_FUNC_INFO << dirName << dbName;
  QDirIterator it(dirName, QDirIterator::Subdirectories);
  parser = new LaneParser(dbName);
  parser->setXalan(! noTransform );
  while (it.hasNext()) {
    it.next();
    qDebug() << it.filePath() << it.fileName();
    QFileInfo fi = it.fileInfo();
    if (fi.isFile()) {
      qDebug() << fi.fileName() << fi.filePath();
      if (parser->readFile(fi.filePath(),false)) {
        parser->parse();
        if (dbUpdate)
          parser->updateDb();
    if (dumpRoots)
      parser->dumpRoots();
      }
    }
  }
  delete parser;
  emit(finished());
}
void SqlTask::run() {
  /*
    QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE");
    db.setDatabaseName("../lane.sqlite");
    bool ok = db.open();
    qDebug() << "db open" << ok;

    QSqlQuery query;
    query.prepare("INSERT INTO words (root,word,node) "
    "VALUES (:root, :word, :node)");
    for (int i=0;i < 100;i++) {
    query.bindValue(":root", "dddd");
    query.bindValue(":word", "Bart");
    query.bindValue(":node", "Simpson");
    ok = query.exec();
    qDebug() << "insert" << ok;
    if ( ! ok ) {
    qDebug() << query.lastError();
    }
    }
    db.close();
  */
  qDebug() << "doing nothing";
  emit(finished());
}
