#!/bin/sh
# enable extended globbing
shopt -s extglob

ARGV0=`basename $0`

#=========================================================================================================
#
# This the PIPA release tool
#
# It does from scratch a clean build and generate a TR package for PIPA
#
# All platforms are supported
#
# Requirement:
#
#   Qt version 4.73 or later installed on the machine it is being generated
#
#  Created by Carlos Jose Mazieri <carlos.mazieri@nxp.com>
#
#  Date:  Sep 14 2011
#
#=========================================================================================================

#=========================================================================================================
# Syntax:
#   release_pipa.sh [-g -p -n -c -t -q <qmakePath> -i <pi-version> -d -r git-repository] [-f Qtest_file]  <input-TAG> <VERSION> <output-TAG>
#       <input-TAG>  A TAG already created that will be used to build for release
#       <VERSION>    The release version, files will be updated to use this release
#       <output-TAG> the TAG will be merged into "testReleases" branch if it starts with "RC_" or "master" branch if it starts with "REL"
#      -g           do NOT install the TR as global Package in MTR
#      -p           do NOT install in local repository neither in the global
#      -n           do NOT clean tmp area
#      -c                  do NOT check in any file in git
#      -t                  do NOT run automated tests (skip them)
#      -q qmakeFullPath    is an optional qmake PATH
#      -i PI-VERSION       attach pipa to a specific PI version (default use from environment)
#      -d                  do not push changes into GIT repository it uses --dry-run in 'git push' command
#      -r git-repository   another GIT repository than the official, it is useful for testing, avoid pushing errors against official repository
#      -o owners     List of owners for the install_pkg, for example:  -o "r52652 nxa07994"
#
#
# Simplified Syntax for running tests only, using -f Qtest_file
#
#  release_pipa.sh [-q <qmakePath>] [-i <pi-version>] [-r git-repository] <-f Qtest_file> <input-TAG>
#  release_pipa.sh [-q <qmakePath>] [-i <pi-version>] [-r git-repository] -PI    <input-TAG>
#=========================================================================================================
#================================================================================
#
##   TO MAKE releases for RH5 and RH6
##  It needs to be done in two steps,  first in machine and then build in other
#
#  * Choose a machine either RH5 or RH6 (do this in a NFS path to use the same path on another machine)
#  *  Choose a NFS path that is visible in both machines (one machine RH5 and other RH6)
#  *  Log into first machine
#  *  Execute the build without saving anything:     release_pipa.sh -n -p -n -c <TAG/BRANCH> <RELEASE> [RELEASE-NOTES-draft]
#  *  Log into another machine (RH5 or RH6 depending on your first build)
#  *  Execute the final build, new saving:          release_pipa.sh   <TAG|BRANCH> <RELEASE> [RELEASE-NOTES-draft]
#
#   The build generates tmp_pipa_release/nxp-pipa-/RELEASE/
#                                                             env  meta  x86_64-linux-glibc2.12 x86_64-linux-glibc2.5
#================================================================================


#=========================================================================================================
#  CHANGE: December 2024 / January 2025, nxf52989: support for cmake, removed unnecessary uptions.
#=========================================================================================================


GIT_DIR=/run/pkg/OSS-git-/2.7.2/bin
if [ ! -x "$GIT_DIR/git" ]
then
   GIT_DIR=/run/pkg/OSS-git-/2.20.1/bin
fi
if [ ! -x "$GIT_DIR/git" ]
then
   GIT_DIR=/bin
fi

GIT=$GIT_DIR/git
GITK=$GIT_DIR/gitk



GIT_URL="https://$USER@bitbucket.sw.nxp.com/scm/de/pipa.git"

GIT_MERGE_NON_FAST_FORWARD="--no-ff"  ## making no-ff default for merges, to change set GIT_MERGE_NON_FAST_FORWARD=""


GIT_TEST_REPOSITORY=""
GIT_PUSH_DRY_RUN=""

PIPA_EXE=./bin/pipa_bin
PIPA_EXE_DEB=${PIPA_EXE}_debug
PIPA_PRO=../code/pipa.pro
PIPA_MKF=pipa.mk
USING_GIT_TAG=1
USING_GIT_BRANCH=2
USING_GIT_TAG_OR_BRANCH=$USING_GIT_TAG

RELEASE_UNKOWN=0
RELEASE_CANDIDATE=1
RELEASE_PRODUCTION=2
RELEASE_TESTONLY=3
RELEASE_TYPE=$RELEASE_UNKOWN
REGRESSION_CONTROL_FILE=""

TEST_RELEASE_BRANCH=testReleases
MASTER_BRANCH=master
TEST_ONLY_BRANCH=testOnly
RELEASE_BRANCH=""

## using Red Hat 5 or 6
RH8=`uname -r | grep el8`
RH7=`uname -r | grep el7`
RH6=`uname -r | grep el6`
RH5=`uname -r | grep el5`


QMAKE_QT5="/bin/qmake-qt5"

# cmake default path is /usr/bin/cmake. Also by default - using cmake is false. Will be set later on to 1. If needed, of course
CMAKE="/usr/bin/cmake"
USE_CMAKE=0

STRIP="/bin/strip"

DEFAULT_PI_PACKAGE=`tr.findpolicy pi | awk 'NR==3 {print $3}'`


CLEAN_TMP_DIR="yes"

RM="/bin/rm -f"
RM_FOLDER="$RM -r"

INPUT_TAG=""
RELEASE_VERSION=""
OUTPUT_TAG=""
CHECK_IN_GIT=1

OWNERS=""

PIPA_RELEASE_COMMENT=""

SUBMODULE_STATUS=""

STOP_COUNTER=0

DEBUG=0        ## 1=DEBUG 0=NoDebug


showHelp()
{
   echo
   echo "$ARGV0  [-h|-H|-help|--help]  [ -n -c -d -debug ] [-q qmakeFullPath] [-m cmakeFullPath] [-p piPackage] [-r gitRepo] [-o owners ] <input-TAG> <VERSION> <output-TAG>"
   echo "  It does the PIPA releasing procedure: Building and Packaging as TR package"
   echo "  Options:"
   echo "      -h|-H|-help|--help  shows the help and exit"
   echo "      -n                  do NOT clean tmp area after building and packaging (useful for testing)"
   echo "      -c                  do NOT check in any file in GIT (useful for testing)"
   echo "      -q qmakeFullPath    is an optional qmake PATH. The default is: $QMAKE_QT5"
   echo "      -m cmakeFullPath    is an optional cmake PATH. The default is: $CMAKE. Note: if specified, then cmake will be used instead of qmake."
   echo "      -p pi Package       is an optional pi package. I.E. -p /pkg/nxp-pi-/2024.2.2  . The default is: $DEFAULT_PI_PACKAGE"
   echo "      -d                  do NOT push changes into GIT repository it uses --dry-run in 'git push' command"
   echo "      -r git-repository   git-repository   another GIT repository than the official, it is useful for testing, avoid pushing errors against official repository"
   echo "      -o owners           List of owners for the install_pkg, for example:  -o \"r52652 nxa07994\""
   echo "      -debug              runs in debug mode, also puts pauses and waits for pressing the [ENTER] key"
   echo
}

debug()
{
   if [ $DEBUG -eq 1 ]
   then
     STOP_COUNTER=`expr $STOP_COUNTER + 1`
     echo
     read  -p "debug/stop point, press CTRL-C to stop or <RETURN> to continue ..."  NOTHING_HERE
   fi
}

#
# returns:  1 the path is fullpath, 0 not fullpath
isFullPath()
{
   ret=0
    fullpath=` echo $1 | grep "^/"`
   if [ "$fullpath" != "" ]
   then
       ret=1
   fi
   return $ret;
}


getGitTag() ## $1 = TAG, checks if the TAG exists
{

   tags=`$GIT tag`
   for t in $tags
   do
      if [ "$t"  = "$1" ]
      then
         ## save information that we are using a TAG from git
         USING_GIT_TAG_OR_BRANCH=$USING_GIT_TAG
         echo $1
         return
      fi
   done

    # to use Branches , uncoment next lines
    branches=`$GIT branch | awk '{print $NF}'`
    for b in $branches
    do
        if [ "$b"  = "$1" ]
        then
            ## save information that we are using a BRANCH instead of TAG
            USING_GIT_TAG_OR_BRANCH=$USING_GIT_BRANCH
            echo $1
            return
        fi
    done
}

doesBranchExist() # $1  = branch
{
      branches=`$GIT branch -a |  awk -F/ '{print $(NF)}' | awk '{print $(NF)}' | sort -u`
      for b in $branches
      do
         if [ "$b"  = "$1" ]
         then
           return 0
         fi
      done
      return 1
}

getReleaseArgument() # just fills the variables related to the RELEASE (TAG, VERSION and OUTPUT_TAG)
{
    if [ "$INPUT_TAG" = "" ]
    then
         INPUT_TAG=$1
    else
         if [ "$RELEASE_VERSION" = "" ]
         then
                RELEASE_VERSION=$1
         else
                OUTPUT_TAG=$1
                isRC=`echo $1 | grep -e "^RC_"`
                if [ "$isRC" != "" ]
                then
                   RELEASE_TYPE=$RELEASE_CANDIDATE
                   RELEASE_BRANCH=${TEST_RELEASE_BRANCH}_${INPUT_TAG}_${OUTPUT_TAG}
                fi
                ## check for ouput-TAG must be "RC_<tag>"
                if [ $RELEASE_TYPE -eq $RELEASE_UNKOWN -o "$OUTPUT_TAG" = "RC_" ]
                then
                   echo "The 'output-TAG must be in the form 'RC_<tag>' to indicate it is a Release Candidate -- ${OUTPUT_TAG}"
                   exit 0
                fi
         fi
    fi
}

#=========================================================================================================
# it builds a Qt project
# parameters:
#                the project pathname
#                the final target (it should match with project file)
#                makefile name (it will deleted after building)
#                config variable
#=========================================================================================================
buildPipa()
{
   pro=$1
   target=$2
   mk=$3
   config=$4
   $RM  $target
   echo "LD_LIBRARY_PATH is: $LD_LIBRARY_PATH"
   echo "=============================================================="
   echo "Input variables: pro: $pro, target: $target, mk: $mk, config:$config"
   echo "=============================================================="
   if [ -f $mk  ]
   then
     make -f $mk distclean
   fi
   debug
   qmakeCmd="$QMAKE \"CONFIG += $config\" \
         \"DEFINES += PIPA_VERSION=$PIPA_VERSION_FOR_COMPILER PIPA_SOURCE_TAG=$PIPA_SOURCE_TAG_FOR_COMPILER\"  \
         $pro  -o $mk"
   echo "doing qmake, using $qmakeCmd"
   $QMAKE "CONFIG += $config" \
         "DEFINES += PIPA_VERSION=$PIPA_VERSION_FOR_COMPILER PIPA_SOURCE_TAG=$PIPA_SOURCE_TAG_FOR_COMPILER"  \
         $pro  -o $mk


   if [ $? -ne 0 ]
   then
      echo "qmake error from [$QMAKE]"
      echo "Verify Qt instalation, required version is 5.12.11 or later"
      exit 1
   fi
   echo
   echo "doing make, generating `pwd`/compile.log, plase wait ..."
   make -f $mk -j30  > compile.log 2>&1
   if [ $? -ne 0 -o ! -x  $target ]
   then
      echo "Error on build for $pro"
      exit 1
   fi
   echo "make complete ..."
   echo
   if [ "$config" = "RELEASE" ]
   then
      $STRIP $target
   fi
   make -f $mk clean
   $RM  $mk
}

buildPipa_cmake()
{

   pro=$1
   codeArea=$(dirname "$pro")
   #target=$(basename $2)
   target=$2
   mk=$3
   config=$4
   CMAKE_CXX_COMPILER=`tr.which g++`
   CMAKE_PREFIX_PATH="/usr"

   $RM  $target
   echo "LD_LIBRARY_PATH is: $LD_LIBRARY_PATH"
   echo "=============================================================="
   echo "Input variables: pro: $pro, target: $target, mk: $mk, config:$config"
   echo "=============================================================="
   debug

   if [ -n "$RH7" ]; then
        CMAKE_PREFIX_PATH="/home/pipaproj/development/pipa_dependencies/install/x86_64-linux3.10-glibc2.17/qt-5.12.11"
   fi



   # Form cmake command
   cmakeCmd="$CMAKE -S $codeArea \
-B $BUILD_DIR \
-DCMAKE_PREFIX_PATH:PATH=$CMAKE_PREFIX_PATH \
-DCMAKE_CXX_COMPILER:FILEPATH=$CMAKE_CXX_COMPILER \
-DCMAKE_GENERATOR:STRING=Ninja \
-DPIPA_VERSION:STRING="${PIPA_VERSION}" \
-DPIPA_SOURCE_TAG:STRING="${PIPA_SOURCE_TAG}" \
-DCMAKE_BUILD_TYPE:STRING=Release"

   echo
   echo "===================================================="
   echo "Starting cmake build..."
   echo "Executing: "
   echo "$cmakeCmd"
   echo
   $cmakeCmd

   if [ $? -ne 0 ]
   then
      echo "Cmake command ($CMAKE) failed. Cannot continue...sorry"
      exit 1
   fi
   echo
   echo "Doing CMAKE BUILD, generating `pwd`/compile.log, please wait ..."
   $CMAKE --build $BUILD_DIR | tee -a compile.log
   if [ $? -ne 0 -o ! -x  $BUILD_DIR/../pipaBuild/bin/pipa_bin ]
   then
      echo "CMAKE BUILD Failed. Cannot continue...sorry"
      exit 1
   fi

   echo "CMAKE Build for target $CMAKE_TARGET completed!"
   echo "===================================================="
   echo
}

#=========================================================================================================
# it builds a Qt project
# parameters:
#                the project pathname
#                the final target (it should match with project file)
#                makefile name (it will deleted after building)
#=========================================================================================================
buildInReleaseMode()
{
   if [ $USE_CMAKE -eq 1 ]; then

      buildPipa_cmake $1 $2 $3 'RELEASE'
   else
      buildPipa $1 $2 $3 'RELEASE'
   fi
   debug
}


buildInDebugMode()
{
  if [ $USE_CMAKE -eq 1 ]; then
    :
  else
    buildPipa $1 $2 $3 'RELEASE_DEBUG'
  fi
  debug
}





#=========================================================================================================
# It gets the architecture name reagarding TR standards
#
# It is necessary to create the TR package.
# The platforms names related to TR standards are:
#   x86_64-linux-glibc2.5   ->  Red Hat 5 64 bits
#   i686-linux-glibc2.5     ->  Red Hat 5 32 bits
#   x86_64-linux-glibc2.3.4 ->  Red Hat 4 64 bits
#   i686-linux-glibc2.3.4   ->  Red Hat 4 32 bits
#   sparc-solaris           ->  Solaris 32 bits
#   sparc64-solaris         ->  Solaris 64 bits
#=========================================================================================================
getArchitecture()
{
    $WORK_BIN/tools/getTrArchString.py
}


cleanReleaseArea()
{
   if [ "$CLEAN_TMP_DIR" = "yes" ]
   then
        $RM_FOLDER $WORK_BIN
        $RM_FOLDER $WORK_DEV
        $RM_FOLDER $PIPA_INSTALL_ROOT
        $RM_FOLDER $TMP_DIR
   fi
}


checkInAndTag()
{
  if [ $CHECK_IN_GIT -eq 1 ]
  then
     cd $WORK_DIR
     if [ $? -ne 0 ]
     then
         echo "ERROR: directory $WORK_DIR no longer exists"
         exit 1
     fi
     CMD="$GIT commit -a -m \'$PIPA_RELEASE_COMMENT\'"
     echo $CMD
     $GIT commit -a -m "$PIPA_RELEASE_COMMENT"
     if [ $? -ne 0 ]
     then
         echo "ERROR: on git commit"
         exit 1
     fi

     if [ $RELEASE_TYPE -eq $RELEASE_PRODUCTION ]
     then
         echo "Production Release, will merge the branch $RELEASE_BRANCH into master ..."
         $GIT checkout master
         if [ $? -ne 0 ]
         then
            echo "ERROR: on git checkout master"
            exit 1
         fi
         $GIT merge $GIT_MERGE_NON_FAST_FORWARD -m "merged by $PIPA_RELEASE_COMMENT" ${RELEASE_BRANCH}
         if [ $? -ne 0 ]
         then
            echo "ERROR: on git merge"
            exit 1
         fi
         $GIT submodule update --recursive
         submodule_status=`$GIT submodule status`
         if [ "$SUBMODULE_STATUS" != "$submodule_status"]; then
            echo "ERROR: submodule status does not match with input tag ${INPUT_TAG}: $SUBMODULE_STATUS"
            exit 1
         fi
         debug
         RELEASE_BRANCH=master
     fi

     CMD="$GIT tag -a -m \'created by $PIPA_RELEASE_COMMENT\'  $OUTPUT_TAG"
     echo $CMD
     debug
     $GIT tag -a -m "created by $PIPA_RELEASE_COMMENT"  $OUTPUT_TAG
     if [ $? -ne 0 ]
     then
         echo "ERROR: on git tag"
         exit 1
     fi
  fi

#   echo "========== file $1 being checked in "
#   cat $1
#   echo "=========="
}
SetupDependencyLibs()
{
   sourceDir=$1
   arch=`getArchitecture`

   qtLibDir=$sourceDir/lib/$arch/qt-5.12.11
   gccLibDir=$sourceDir/lib/$arch/gcc-10.3.0
   # We need LD_LIBRARY_PATH and PATH to point to lib/ARC directory
   export LD_LIBRARY_PATH=$qtLibDir/lib:$gccLibDir/lib64:$gccLibDir/lib
   export PATH=$qtLibDir/bin:$gccLibDir/bin:${PATH}
}

FixBinaryDependencies()
# no worries... its gonna be executed just in qmake mode.
# cmake should take care for patchelf as well as for libs
{
   sourceDir=$1
   pkgDir=$2
   arch=`getArchitecture`

   rsync -aHv $sourceDir/$arch/lib/. $pkgDir/lib

   if [ -n "$RH7" ]; then
      cd $pkgDir/bin
      ln -sv ../lib/plugins/* ./
      echo "current dir is: `pwd` ..."
      /pkg/OSS-patchelf-/0.10/x86_64-linux/bin/patchelf --force-rpath --set-rpath '$ORIGIN/../lib' pipa_bin
      /pkg/OSS-patchelf-/0.10/x86_64-linux/bin/patchelf --force-rpath --set-rpath '$ORIGIN/../lib' pipa_bin_debug
   fi
}


#=========================================================================================================
#  MAIN
#=========================================================================================================

##check input parameters

if [ $# -gt 0 -a "$1"  != "" ]
then
   while [ "$1" != "" ]
   do
     case $1 in
      -debug) DEBUG=1; set -vx
               shift
               ;;
        -n)     CLEAN_TMP_DIR="no"
                shift;;
        -c)     CHECK_IN_GIT=0
                shift;;
        -h|-H|-help|--help) showHelp
                            exit 0;;
        -q)     shift
                if [ -x $1 ]
                then
                    QMAKE_QT5=$1
                else
                    echo "Unknown option $option try -h to see the options"
                    exit 1
                fi
                shift
                ;;
        -m)     shift
                if [ -x $1 ]
                then
                    CMAKE=$1
                    USE_CMAKE=1
                    echo "Using cmake build system. Cmake found at $CMAKE"
                else

                    echo "Unknown option $option try -h to see the options"
                    exit 1
                fi
                shift
                ;;
        -p)     shift
                if [ -x $1 ]
                then
                    DEFAULT_PI_PACKAGE=$1
                    echo "Using cmake build system. Cmake found at $DEFAULT_PI_PACKAGE"
                else

                    echo "Unknown option $option try -h to see the options"
                    exit 1
                fi
                shift
                ;;


         -d)    GIT_PUSH_DRY_RUN="--dry-run"
                shift
                ;;
         -r)    shift
                GIT_TEST_REPOSITORY=$1
                shift
                ;;
         -o)    shift
                OWNERS=$1
                shift
                ;;
         *)     getReleaseArgument $1
                shift
                ;;
    esac
  done
fi


if [ -x $QMAKE_QT5 ]
then
    QMAKE=$QMAKE_QT5
else
    echo "qmake is not at $QMAKE_QT5"
    echo "please identify your qmake from Qt version 5.12.11 or later"
    exit 1
fi


PIPA_RELEASE_COMMENT="PiPA release for version $RELEASE_VERSION from tag $INPUT_TAG"

echo "CLEAN_TMP_DIR=$CLEAN_TMP_DIR QMAKE_QT5=$QMAKE_QT5 INPUT_TAG=$INPUT_TAG RELEASE_VERSION=$RELEASE_VERSION \
CHECK_IN_GIT=$CHECK_IN_GIT REGRESSION_CONTROL_FILE=$REGRESSION_CONTROL_FILE GIT_TEST_REPOSITORY=$GIT_TEST_REPOSITORY PIPA_RELEASE_COMMENT=$PIPA_RELEASE_COMMENT"

if [ "$INPUT_TAG" = "" -o "$RELEASE_VERSION" = "" -o "$OUTPUT_TAG" = "" ]
then
     showHelp
     exit 0
fi


## to build for more than one platform we expect to do that in a NFS area
TMP_DIR="`pwd`/tmp_pipa_release"
mkdir $TMP_DIR 2>/dev/null
echo
echo "==== working on directory $TMP_DIR"

WORK_DIR=$TMP_DIR/pipa_release_${OUTPUT_TAG}
if [ -d $WORK_DIR ]
then
   echo "removing old directory $WORK_DIR ..."
   $RM_FOLDER $WORK_DIR
fi
mkdir -p $WORK_DIR 2>/dev/null

##get from GIT repository
cd $WORK_DIR
userName=`phone $USER |awk -F ":" '{print $2}'`
userEmail=`phone $USER |awk -F ":" '{print $4}'`
$GIT config --global user.name  "$userName"
$GIT config --global user.email "$userEmail"

if [ "$GIT_TEST_REPOSITORY" != "" ]
then
       GIT_URL=$GIT_TEST_REPOSITORY
       echo "using GIT test repository $GIT_URL ..."
fi

# changed to only download one tag https://stackoverflow.com/questions/791959/download-a-specific-tag-with-git
CMD="$GIT clone -b $INPUT_TAG --single-branch --depth 1 $GIT_URL"
echo $CMD
$GIT --version
#debug
$GIT clone -b $INPUT_TAG --single-branch --depth 1 $GIT_URL
if [ $? -ne 0 ]
then
    echo
    echo "ERROR:  could not clone using cmd:  $GIT_URL"
    exit 1
else
    cd pipa
    if [ $? -ne 0 ]
    then
      echo
      echo "ERROR:  maybe clone failed, 'pipa' directory doe not exist"
      exit 1
    fi
    echo "$GIT submodule init"
    $GIT submodule init
fi
debug

## we are inside $WORK_DIR/pipa, make this the $WORK_DIR
WORK_DIR=`pwd`
WORK_BIN=$WORK_DIR/bin
WORK_LIB=$WORK_DIR/lib
WORK_DEV=$WORK_DIR/code
WORK_CPPLIB=$WORK_DIR/cpplib/tools/bin


## check input tag
inputTagIsOK=`getGitTag $INPUT_TAG`
if [ "$inputTagIsOK" = "" ]
then
     echo "ERROR:  there is no TAG with the name \'$INPUT_TAG\'"
     exit
fi

OK=0
CMD=""


#checkout right branch doing a merge with the TAG
CHECKOUT="checkout"
CHECKOUT_TAG=""
doesBranchExist $RELEASE_BRANCH
if [ $? -ne 0 ]
then
   echo "branch $RELEASE_BRANCH does not exist, it needs to be created"
   CHECKOUT="checkout -b"
   CHECKOUT_TAG=${INPUT_TAG}
fi

echo "current dir is: `pwd` ..."
CMD="$GIT $CHECKOUT $RELEASE_BRANCH $CHECKOUT_TAG"
echo "checkouting the branch: $CMD ..."

debug

$CMD
if [ $? -ne 0 ]
then
   echo "ERROR: GIT checkout the branch: $CMD"
   exit
fi


echo "$GIT submodule init using"
$GIT submodule init

echo "current branch is: `$GIT branch | grep \*` ..."

debug

#if checked out with the TAG merge is not necessary
if [ "$CHECKOUT_TAG" = "" ]
then
      echo "merging the tag ${INPUT_TAG}"
      debug
      #merge the input TAG
      # --squash = do not do a real merge merge is done on the next commit,
      # --no-ff  = generate commit record event fast-forward merge was performed
      #  they cannot be used at same time

      CMD="$GIT merge $GIT_MERGE_NON_FAST_FORWARD -m 'merged by $PIPA_RELEASE_COMMENT' ${INPUT_TAG}"
      echo $CMD
      $GIT merge $GIT_MERGE_NON_FAST_FORWARD -m "merged by $PIPA_RELEASE_COMMENT" ${INPUT_TAG}
      if [ $? -ne 0 ]
      then
         echo "ERROR: GIT merge ERROR in cmd: $CMD"
         exit
      fi
fi

SUBMODULE_STATUS=`$GIT submodule status`
echo "current submodule status is: $SUBMODULE_STATUS"
echo "Updating submodules ... "
OTHER_CPPLIB=`/bin/grep  cpplib.git .git/config | grep $USER`
if [ "$OTHER_CPPLIB" = "" ]
then
    /bin/cp  .git/config  dot_git_config
    /bin/grep -v cpplib.git .git/config > config.submodule
    /bin/echo -e "\turl = https://${USER}@bitbucket.sw.nxp.com/scm/de/cpplib.git" >> config.submodule
    /bin/cp config.submodule  .git/config
fi
CPPLIB_URL=`/bin/grep cpplib .git/config`
debug
$GIT submodule update --recursive
if [ "$OTHER_CPPLIB" = "" ]
then
    /bin/cp dot_git_config .git/config
fi
debug

SetupDependencyLibs $WORK_DIR


cd $WORK_BIN
PIPA_VERSION=`grep -i VERSION README_PIPA-GUI | awk '{print $2}'`
PIPA_SOURCE_TAG=`grep -i TAG README_PIPA-GUI | awk '{print $2}'`

if [ "$PIPA_SOURCE_TAG" != "$OUTPUT_TAG" -o "$PIPA_VERSION" != "$RELEASE_VERSION" ]
then
       PIPA_SOURCE_TAG=$OUTPUT_TAG
       PIPA_VERSION=$RELEASE_VERSION
       chmod 644 README_PIPA-GUI
       echo "VERSION: $PIPA_VERSION"   > README_PIPA-GUI
       echo "TAG: $PIPA_SOURCE_TAG"   >> README_PIPA-GUI
fi

##change bin/pipa and bin/pipa.version
if [ "`grep PIPAVERSION= bin/pipa.version | grep $PIPA_VERSION`" = "" ]
then
      chmod u+w  bin/pipa.version
      cp bin/pipa.version  _tmp_pipa.version_$$
      sed -e s/PIPAVERSION=.*/PIPAVERSION=\"$PIPA_VERSION\"\;/  _tmp_pipa.version_$$      > bin/pipa.version
      rm -rf _tmp_pipa.version_$$
fi

##check if it was changed
if [ "`grep PIPAVERSION= bin/pipa.version | grep $PIPA_VERSION`" = "" ]
then
   echo "could not change bin/pipa.version"
   exit 1
fi


change_bin_pipa=0
cp bin/pipa  _tmp_pipa_$$

#change bin/pipa
if [ "`grep PKGVERSION=\'nxp\-pipa\-  _tmp_pipa_$$ | grep $PIPA_VERSION`" = "" ]
then
    chmod u+w  bin/pipa
    sed -e s%PKGVERSION=.*%PKGVERSION=\'nxp-pipa-/$PIPA_VERSION\'% _tmp_pipa_$$   > bin/pipa
    change_bin_pipa=1
fi

$RM _tmp_pipa_$$


if [ "`grep PKGVERSION=\'nxp\-pipa\-   bin/pipa | grep $PIPA_VERSION`" = "" ]
then
   echo "could not put PKGVERSION=$PIPA_VERSION in bin/pipa"
   exit 1
fi

BUILD_DIR=$TMP_DIR/build_pipa_release_${OUTPUT_TAG}/release_script_pipaBuildDir
echo "Building in $BUILD_DIR"
if [ -e $BUILD_DIR ]
then
  $RM_FOLDER $BUILD_DIR
fi
mkdir -p $BUILD_DIR/bin


cd $BUILD_DIR
PIPA_PRO=$WORK_DIR/code/pipa.pro
## in compilation it needs to generate a line like:  -DPIPA_VERSION=\"2011.10-b1\" -DPIPA_SOURCE_TAG=\"X_Release_2011.10-b1\"
PIPA_VERSION_FOR_COMPILER="\\\\\\\"${PIPA_VERSION}\\\\\\\""
PIPA_SOURCE_TAG_FOR_COMPILER="\\\\\\\"${PIPA_SOURCE_TAG}\\\\\\\""

buildInReleaseMode   $PIPA_PRO  $PIPA_EXE      $PIPA_MKF
buildInDebugMode     $PIPA_PRO  $PIPA_EXE_DEB  $PIPA_MKF

cd $WORK_BIN

#=========================================================================================================
# TR packaging
#=========================================================================================================
ARC=`getArchitecture`

echo "Architecture: $ARC"


PIPA_INSTALL_ROOT=$TMP_DIR/nxp-pipa-/$PIPA_VERSION
PKG_DIR=$PIPA_INSTALL_ROOT/$ARC
if [ -e $PKG_DIR ]
then
  $RM_FOLDER $PKG_DIR
  echo -e "\n Removed directory $PKG_DIR"
fi

debug


mkdir -p $PKG_DIR

if [ $USE_CMAKE -eq 1 ]; then
    # OK, cmake!  We just have to copy (rsync...better) everything from $BUILD_DIR/../pipaBuild/ to the TR package dir.
    # pipaFunctions.cmake/CMakeLists.txt took care for rsyncing
    rsync -aHv --exclude=$ARGV0 $BUILD_DIR/../pipaBuild/. $PKG_DIR
else
    #Qmake
    rsync -aHv --exclude=.SYNC --exclude=.empty --exclude=$ARGV0 --exclude=tools --exclude=lib ./. $PKG_DIR
    rsync -aHv --exclude=.SYNC --exclude=.empty --exclude=$ARGV0 --exclude=tools --exclude=lib $BUILD_DIR/. $PKG_DIR
    mkdir -p $PKG_DIR/lib
    FixBinaryDependencies $WORK_LIB $PKG_DIR
    if [ -r $WORK_DEV/config ]
    then
       ## make sure packahge directory exists and it is not a link
       if [ -h $PKG_DIR/config -o ! -r  $PKG_DIR/config ]
       then
          $RM_FOLDER $PKG_DIR/config
          /bin/cp -r $WORK_DEV/config $PKG_DIR
       fi
    fi

fi


mkdir -p $PIPA_INSTALL_ROOT/env $PIPA_INSTALL_ROOT/meta 2>/dev/null

if [ ! -e "$PIPA_INSTALL_ROOT/env/common.mtr" ]
then
cat >$PIPA_INSTALL_ROOT/env/common.mtr <<EOF
# Beginning
#
# Path to directories
prepend PATH <RUNROOT>/bin
prepend MANPATH <RUNROOT>/man
prepend INFOPATH <RUNROOT>/info
set PIPAHOME <RUNROOT>/bin

# End
EOF
fi


if [ ! -e "$PIPA_INSTALL_ROOT/env/#all" ]
then
cat >$PIPA_INSTALL_ROOT/env/#all <<EOF

env PATH prepend \${TOOL_ROOT}/bin
include tool pi PUBLISHMETHOD
env MANPATH prepend \${TOOL_ROOT}/man
env INFOPATH prepend \${TOOL_ROOT}/info
env PIPAHOME set \${TOOL_ROOT}/bin

EOF
fi


if [ ! -e "$PIPA_INSTALL_ROOT/env/pkgbin" ]
then
cat >$PIPA_INSTALL_ROOT/env/pkgbin <<EOF
bin/pipa
bin/pipa.ws
bin/pipa.wsenv
bin/dynamicFlowLoading
bin/pipa.callback.post
bin/pipa.envcallback
EOF
fi


if [ ! -e "$PIPA_INSTALL_ROOT/meta/dependencies" ]
then
cat >$PIPA_INSTALL_ROOT/meta/dependencies <<EOF
$DEFAULT_PI_PACKAGE
EOF
fi

if [ ! -e "$PIPA_INSTALL_ROOT/meta/rel.nxp-pipa-$RELEASE_VERSION" ]
then
cat $WORK_BIN/RELEASE_NOTES >$PIPA_INSTALL_ROOT/meta/rel.nxp-pipa-$RELEASE_VERSION
fi



compile_env  -force $PIPA_INSTALL_ROOT -o $PIPA_INSTALL_ROOT
PKG_STATUS=$?

/bin/chmod -R 755 $TMP_DIR/nxp-pipa-


if [ $CHECK_IN_GIT -eq 1 ]
then
   ### Check in and TAG if it was OK
   checkInAndTag
   echo -n "Changes committed and tag $OUTPUT_TAG created, would you like to check using \'gitk\' (Y/n)?: "
   read yes
   if [ "$yes" != "N" -a "$yes" != "n" ]
   then
         $GITK
   fi

   FORCE_PUSH=""
   echo -n "Would you like to push everything to the server (Y/n)?: "
   read yes
   if [ "$yes" != "N" -a "$yes" != "n" ]
   then
      ## first push uses --dry-run to see if there is any error
      ## if so ask the user if he/she wants to use --force in push command
      if [ "$GIT_PUSH_DRY_RUN" = "" ]
      then
           CMD="$GIT push --tags --dry-run --verbose origin $RELEASE_BRANCH"
           echo "testing push using command: $CMD"
           debug
           `$CMD`
           if [ $? -ne 0 ]
           then
                echo "Push test failed, using \'--force\' should work, would you like to FORCE pushing everything to the server (y/N)?:"
                read yes
                if [ "$yes" = "Y" -o "$yes" = "y" ]
                then
                     FORCE_PUSH="--force"
                fi
           fi
      fi
      ## now the final push
      CMD="$GIT push $FORCE_PUSH --tags $GIT_PUSH_DRY_RUN --verbose origin $RELEASE_BRANCH"
      echo "pushing changes to the server cmd: $CMD"
      debug
      `$CMD`
      if [ $? -ne 0 ]
      then
           echo "ERROR on push changes to the server"
           exit 1
      fi
   fi
fi

cleanReleaseArea





