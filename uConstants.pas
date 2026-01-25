{
  s->c						c->s
  0	stop
  send: msg (str)
  5	flag: enable adr(int)
  6	req: enabled state
  send: state mode (int)
  10	move(int,int,int)
  15	act: sit/stand (int)
  20	npcsel (int)
  30	npcdlg (int)
  31	req: current dlg				send: dlg (str)
  32	req: current cb					send: cb (str)
  40	req: inv count					send: inv count (int)
  41	req: inv item by index (int)			send: inv item (int,int) //id,cnt
  50	req: skills count (int)				send: skills count(int)
  51	req: skill id by index (int)			send: skill id(int)
  60	flag: set use hp potion(int)
  70	act: send packet (str)
  80	act: delay (int)
}

unit uConstants;

interface

const
    actStop = 0; // stop activity and finish execution
    actDelay = 5;
    // actMsgFromDll = 5; // send: msg (str)
    actMove = 10; // move(int,int,int)
    actNpcSel = 20;
    actNpcDlg = 30;
    actDlgSel = 40;
    actDlgTextToDLL = 50;
    actCBTextToDLL = 60;
    //    actStrToDLL = 70;
    actStrFromDLL = 80;
    actIntToDLL = 90;
    actSitStand = 100;  // from DLL: p1 mode(0-1), 1 = stand
    actFaceControl = 110; // from DLL: p1 mode(0-4), p2 state(0-1)

implementation

end.

