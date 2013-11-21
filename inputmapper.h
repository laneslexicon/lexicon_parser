#ifndef __INPUTMAPPER_H__
#define __INPUTMAPPER_H__
#include <stdlib.h>
#include <stdio.h>
#include "keymap.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
// changed  gunichar -> int
class im_char {
 public:
  int uc;
  QString c;
  int iv;        // input value i.e current char
  int pv;        // previous char
  bool consume;
  bool processed;
};
/*
im_char * im_char_new();
void im_char_free(im_char *);
*/
class InputMapper {
 public:
  InputMapper();

  QList<KeyMap *> maps;
  int pv;      // previous char only set when the key has been processed
  void getMapNames(QStringList &);
  void getScripts(QStringList &);
  void setDebug(bool v) { m_debug = v;}
  QString getScript(const QString & map);
  bool m_debug;
};
InputMapper * im_new();
void im_free(InputMapper *);
bool im_load_map_from_json(InputMapper * map,const char * filename,const char * mapname = 0);
KeyMap * im_get_map(InputMapper *,const QString &);
im_char * im_convert(InputMapper *,const QString & ,int current,int prev);
void load_properties(KeyMap *,QJsonObject);
void load_koi(KeyMap *,QJsonObject);
void load_combinations(KeyMap *,QJsonObject);
void load_unicode(KeyMap *,QJsonObject);
KeyEntry * get_key_entry(QJsonObject);
KeyInput * get_key_item(QJsonObject);
bool im_match_diacritics(KeyEntry *,QStringList &) ;
int im_search(KeyMap *,KeyInput *,KeyEntry *,int);
QString im_convert_string(InputMapper * im,const QString & mapping,const QString & source,bool * ok = 0);

/*
gboolean im_has_map(InputMapper *,gchar *);
im_char * im_convert(InputMapper *,gchar *,gchar current,gunichar prev);
im_char * imcontext_convert(InputMapper *,gchar *,gunichar current,gunichar prev);
gunichar im_search(KeyMap * map,KeyInput * ki,KeyEntry * ke,gunichar pchar);
GString * im_convert_string(InputMapper * im,gchar * mapping,gchar * str);
*/
#endif
