#ifndef _XSLTSUPPORT_H
#define _XSLTSUPPORT_H
#include <QString>
#include <QByteArray>
#include <QMap>
#include <QMapIterator>
#include <xalanc/Include/PlatformDefinitions.hpp>
#include <xercesc/util/PlatformUtils.hpp>
#include <xalanc/XalanTransformer/XalanTransformer.hpp>
#include <xalanc/XalanDOM/XalanDOMString.hpp>
#include <iostream>
#include <sstream>

XALAN_USING_XERCES(XMLPlatformUtils)
XALAN_USING_XALAN(XalanTransformer)

//int m_xml_initialized = 0;
XalanTransformer * getXalan();
QString xalanTransform(const QString &,const QString &,QMap<QString,QString> &);
#endif
