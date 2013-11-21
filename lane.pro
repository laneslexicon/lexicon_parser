#-------------------------------------------------
#
# Project created by QtCreator 2013-05-05T10:34:31
#
#-------------------------------------------------

QT       += core
QT       += xml sql

CONFIG   += debug console
QMAKE_CXXFLAGS += -g
greaterThan(QT_MAJOR_VERSION, 4): QT += widgets
TARGET = lane
TEMPLATE = app
#INCLUDEPATH += ../InputMapper
#INCLUDEPATH += /opt/mongo/include
#LIBS += -L/opt/mongo/lib
#LIBS +=  -lmongoclient -lboost_thread-mt -lboost_system -lboost_filesystem
LIBS += -lxalan-c -lxalanMsg -lxerces-c -lxerces-depdom
MOC_DIR = ./moc
OBJECTS_DIR = ./obj
SOURCES += main.cpp \
           task.cpp \
        xsltsupport.cpp \
	keymap.cpp \
	inputmapper.cpp \
        domparser.cpp \
        lanesettings.cpp \
        laneparser.cpp

HEADERS  += xsltsupport.h \
            task.h \
	keymap.h \
	inputmapper.h \
            domparser.h \
            lanesettings.h \
            laneparser.h

#FORMS    += mainwindow.ui
