//+------------------------------------------------------------------+
//|                                             FractalExport.mqh    |
//|  CSV export engine for Fractal_Breakout.                         |
//|                                                                  |
//|  Built on the CCSVExporter pattern: the expert opens the stream  |
//|  in OnInit(), appends one row in OnTester() and closes it in      |
//|  OnDeinit(). Rows are written by the tester agent itself, so      |
//|  several agents share one file in the common folder.             |
//+------------------------------------------------------------------+
#property strict

//--- Column separator constant for CSV output streams
#define CSV_SEPARATOR ","

//--- Trims trailing zeros so 24.000000 lands in the file as 24
string CsvNum(const double value)
  {
   if(value == MathFloor(value) && MathAbs(value) < 1.0e15)
      return IntegerToString((long)value);

   string s = DoubleToString(value, 8);
   int last = StringLen(s) - 1;
   while(last > 0 && StringGetCharacter(s, last) == '0')
      last--;
   if(last > 0 && StringGetCharacter(s, last) == '.')
      last--;
   return StringSubstr(s, 0, last + 1);
  }

//+------------------------------------------------------------------+
//| Identifies the writing process. Every tester agent runs in its    |
//| own data folder, so the last path component is unique per agent.  |
//+------------------------------------------------------------------+
string CsvAgentTag()
  {
   string path = TerminalInfoString(TERMINAL_DATA_PATH);

   int sep = -1;
   for(int i = StringLen(path) - 1; i >= 0; i--)
     {
      ushort ch = StringGetCharacter(path, i);
      if(ch == 92 || ch == 47)   // backslash or slash
        {
         sep = i;
         break;
        }
     }

   string tag = (sep >= 0) ? StringSubstr(path, sep + 1) : path;
   StringReplace(tag, ":", "-");
   StringReplace(tag, " ", "_");

   return (StringLen(tag) > 0) ? tag : "local";
  }

//+------------------------------------------------------------------+
//| Gives each writer its own file: several agents appending to one   |
//| file interleave mid-line and shred the rows.                      |
//+------------------------------------------------------------------+
string CsvPerAgentName(const string filename)
  {
   int dot = StringLen(filename);
   for(int i = StringLen(filename) - 1; i >= 0; i--)
      if(StringGetCharacter(filename, i) == 46)   // dot
        {
         dot = i;
         break;
        }

   return StringSubstr(filename, 0, dot) + "_" + CsvAgentTag() + StringSubstr(filename, dot);
  }

//+------------------------------------------------------------------+
//| CCSVExporter: encapsulates all CSV file I/O for structured export|
//+------------------------------------------------------------------+
class CCSVExporter
  {
private:
   //--- Internal file handle; INVALID_HANDLE when no stream is open
   int               m_handle;

   //--- Stores the resolved file name for diagnostic messages
   string            m_filename;

   //--- Writes the schema header row to the open stream
   bool              WriteHeader(const string &columns[]);

public:
                     CCSVExporter();
                    ~CCSVExporter();

   //--- Opens or creates the target CSV file.
   //--- Pass use_common=true to resolve the path via FILE_COMMON.
   bool              Open(const string filename, const string &columns[],
                          const bool append = true, const bool use_common = true);

   //--- Appends a single result row to the open stream
   bool              WriteRow(const string &prefix[], const double &values[]);

   //--- Flushes and closes the file stream safely
   void              Close();

   //--- Returns true if the stream is currently open and valid
   bool              IsOpen() const { return m_handle != INVALID_HANDLE; }
  };

//+------------------------------------------------------------------+
CCSVExporter::CCSVExporter()
  {
   m_handle   = INVALID_HANDLE;
   m_filename = "";
  }

//+------------------------------------------------------------------+
//| Destructor: releases the handle if the caller neglected Close()  |
//+------------------------------------------------------------------+
CCSVExporter::~CCSVExporter()
  {
   Close();
  }

//+------------------------------------------------------------------+
//| Open: opens or creates the target CSV file.                      |
//|                                                                  |
//| FILE_READ|FILE_WRITE creates the file when missing and never     |
//| truncates an existing one. The share flags matter during         |
//| optimisation: without them the second agent's open fails, and    |
//| the usual fallback to a bare FILE_WRITE would wipe the rows the  |
//| first agent has already written.                                 |
//+------------------------------------------------------------------+
bool CCSVExporter::Open(const string filename, const string &columns[],
                        const bool append = true, const bool use_common = true)
  {
   if(m_handle != INVALID_HANDLE)
     {
      Print("CCSVExporter::Open() - stream already open on [", m_filename, "]. Call Close() first.");
      return(false);
     }

   string resolved = CsvPerAgentName(filename);

   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI |
               FILE_SHARE_READ | FILE_SHARE_WRITE;

   if(use_common)
      flags |= FILE_COMMON;

   if(!append)
     {
      //--- Caller asked for a fresh file: drop the old one first
      FileDelete(resolved, use_common ? FILE_COMMON : 0);
     }

   m_handle = FileOpen(resolved, flags);

   if(m_handle == INVALID_HANDLE)
     {
      PrintFormat("CCSVExporter::Open() - FileOpen failed. Error: %d | File: %s",
                  GetLastError(), resolved);
      return(false);
     }

   m_filename = resolved;

   //--- Header goes in only when the file is genuinely empty
   if(FileSize(m_handle) == 0 && !WriteHeader(columns))
     {
      Close();
      return(false);
     }

   FileSeek(m_handle, 0, SEEK_END);
   return(true);
  }

//+------------------------------------------------------------------+
//| WriteHeader: outputs the schema column header row                |
//+------------------------------------------------------------------+
bool CCSVExporter::WriteHeader(const string &columns[])
  {
   if(m_handle == INVALID_HANDLE)
      return(false);

   string header = "";
   for(int i = 0; i < ArraySize(columns); i++)
      header += (i > 0 ? CSV_SEPARATOR : "") + columns[i];

   if(FileWriteString(m_handle, header + "\n") == 0)
     {
      PrintFormat("CCSVExporter::WriteHeader() - write failed. Error: %d", GetLastError());
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| WriteRow: appends a single data record to the CSV stream         |
//+------------------------------------------------------------------+
bool CCSVExporter::WriteRow(const string &prefix[], const double &values[])
  {
   if(m_handle == INVALID_HANDLE)
     {
      Print("CCSVExporter::WriteRow() - no open stream. Call Open() first.");
      return(false);
     }

   string row = "";
   for(int i = 0; i < ArraySize(prefix); i++)
      row += (i > 0 ? CSV_SEPARATOR : "") + prefix[i];

   for(int i = 0; i < ArraySize(values); i++)
      row += CSV_SEPARATOR + CsvNum(values[i]);

//--- Another agent may have appended since we last wrote
   FileSeek(m_handle, 0, SEEK_END);

   if(FileWriteString(m_handle, row + "\n") == 0)
     {
      PrintFormat("CCSVExporter::WriteRow() - write failed. Error: %d", GetLastError());
      return(false);
     }

   FileFlush(m_handle);
   return(true);
  }

//+------------------------------------------------------------------+
void CCSVExporter::Close()
  {
   if(m_handle != INVALID_HANDLE)
     {
      FileFlush(m_handle);
      FileClose(m_handle);
      m_handle   = INVALID_HANDLE;
      m_filename = "";
     }
  }
//+------------------------------------------------------------------+
