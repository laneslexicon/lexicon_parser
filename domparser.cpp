#include "domparser.h"
DomParser::DomParser() {
  m_parsePass = 0;
}
bool DomParser::readFile(const QString & fileName,bool parse) {
  QFile file(fileName);
  if (!file.open(QFile::ReadOnly | QFile::Text)) {
    std::cerr << "Error: Cannot read file " << qPrintable(fileName)
              << ": " << qPrintable(file.errorString())
              << std::endl;
    return false;
  }
  QString errorStr;
  int errorLine;
  int errorColumn;

  if (! doc.setContent(&file,false,&errorStr,&errorLine,&errorColumn)) {
    std::cerr << "Parse error";
    return false;
  }
  currentFile = fileName;

  if (parse)
    loadDOM();

  return true;
}
bool DomParser::parse() {
  m_parsePass++;
  parseInit(m_parsePass);
  loadDOM();  // the first pass do the translate updating DOM in-place
  flush();    // reset anything
  /**
    re-read the DOM building whatever data structure using the converted
    text
  */
  m_parsePass++;
  parseInit(m_parsePass);
  loadDOM();

}
void DomParser::parseInit(int pass) {
}
void DomParser::flush() {
}
bool DomParser::loadDOM() {
  QDomElement root = doc.documentElement();
  QDomNode child = root.firstChild();
  while (!child.isNull()) {
    //    parseElement(child,tree->invisibleRootItem());
    traverseXml(child);
    child = child.nextSibling();
  }
  parsingComplete(m_parsePass);
  emit(parseComplete(m_parsePass));
  return true;
}
void DomParser::parsingComplete(int pass) {
}
bool DomParser::saveFile(const QString & fileName) {
  QFile outfile(fileName);
  QFileInfo fi(outfile);
  QDir d;
  d.mkpath((fi.absolutePath()));
  if (!outfile.open(QFile::WriteOnly | QFile::Text)) {
    qDebug() << "error opening file" << fileName;
    return false;
  };
  QTextStream out(&outfile);
  out.setCodec("UTF-8");
  doc.save(out,4);
  out.flush();
  outfile.close();
  qDebug() << "saved file" << fileName;
  return true;
}
bool DomParser::writeNode(const QDomNode & node,const QString & fileName) {
  QFile outfile(fileName);
  QFileInfo fi(outfile);
  QDir d;
  d.mkpath((fi.absolutePath()));
  if (!outfile.open(QFile::WriteOnly | QFile::Text)) {
    qDebug() << "error opening file" << fileName;
    return false;
  };
  QTextStream out(&outfile);
  out.setCodec("UTF-8");
  out << node;
  //doc.save(out,4);
  out.flush();
  outfile.close();
  qDebug() << "saved node" << fileName;
  return true;
}
bool DomParser::writeNode(const QDomNode & node,QString & str) {
  QTextStream out(&str);
  out.setCodec("UTF-8");
  out << node;
  //doc.save(out,4);
  out.flush();
  //  qDebug() << "saved node" << str;
  return true;
}
void DomParser::traverseXml(QDomNode& node)
{
  QDomNode domNode = node.firstChild();
  QDomElement domElement;
  QDomText domText;
  //  qDebug() << "-------";
  static int level = 0;

  level++;

  while(!(domNode.isNull()))
  {
    if(domNode.isElement())
    {
      domElement = domNode.toElement();
      if(!(domElement.isNull()))
      {
        //        qDebug() << __FUNCTION__ << "isElement" << level << QString(level, ' ').toLocal8Bit().constData() << domElement.tagName().toLocal8Bit().constData();

        QDomNamedNodeMap nma = domElement.attributes();
        if (domElement.hasAttribute("lang") && (domElement.attribute("lang") == "ar")) {
          //          qDebug() << "arabic coming up";
        }
        //        if (domElement.tagName() == "itype") {
        //          domElement.setTagName("div");
        //        }
        if (domElement.hasAttribute("key")) {
          //          qDebug() << "key" << domElement.attribute("key");
          //          emit(gotKeyNode(&domElement));
        }
        int l = nma.length();
        for(  int i=0; i < l; i++ )
        {
          QDomAttr tempa = nma.item(i).toAttr();
          //          qDebug() << __FUNCTION__ << "isElement"  << level << QString(level, ' ').toLocal8Bit().constData() << "attribute" << i << tempa.name().toLocal8Bit().constData() << tempa.value().toLocal8Bit().constData();
        }
      }
    }

    if(domNode.isText())
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
              // emit gotTextNode(&domText);
              //              domText.setData("xxxxx");
            }
        }
        //
      }
    }

    traverseXml(domNode);
    domNode = domNode.nextSibling();
  }

  level--;
}
