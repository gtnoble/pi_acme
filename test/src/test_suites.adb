with AUnit.Test_Caller;
with Nine_P_Proto_Tests;
with Nine_P_Client_Tests;
with Nine_P_Integration_Tests;
with Acme_Event_Parser_Tests;
with Acme_Raw_Events_Tests;
with Acme_Window_Tests;
with Acme_Integration_Tests;
with Pi_RPC_Tests;
with Pi_Interface_Tests;
with Session_Lister_Tests;
with Pi_Acme_App_Tests;
with Session_History_Tests;
with Tool_URI_Tests;
with Subagent_Integration_Tests;

package body Test_Suites is

   package Proto_Caller is
     new AUnit.Test_Caller (Nine_P_Proto_Tests.Test);
   package Client_Caller is
     new AUnit.Test_Caller (Nine_P_Client_Tests.Test);
   package Nine_P_Int_Caller is
     new AUnit.Test_Caller (Nine_P_Integration_Tests.Test);
   package Event_Parser_Caller is
     new AUnit.Test_Caller (Acme_Event_Parser_Tests.Test);
   package Raw_Events_Caller is
     new AUnit.Test_Caller (Acme_Raw_Events_Tests.Test);
   package Window_Caller is
     new AUnit.Test_Caller (Acme_Window_Tests.Test);
   package Acme_Int_Caller is
     new AUnit.Test_Caller (Acme_Integration_Tests.Test);
   package Pi_RPC_Caller is
     new AUnit.Test_Caller (Pi_RPC_Tests.Test);
   package Pi_Iface_Caller is
     new AUnit.Test_Caller (Pi_Interface_Tests.Test);
   package Session_Lister_Caller is
     new AUnit.Test_Caller (Session_Lister_Tests.Test);
   package App_State_Caller is
     new AUnit.Test_Caller (Pi_Acme_App_Tests.Test);
   package Session_History_Caller is
     new AUnit.Test_Caller (Session_History_Tests.Test);
   package Tool_URI_Caller is
     new AUnit.Test_Caller (Tool_URI_Tests.Test);
   package Subagent_Int_Caller is
     new AUnit.Test_Caller (Subagent_Integration_Tests.Test);

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      --  Nine_P.Proto tests
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Qid round-trip",
         Nine_P_Proto_Tests.Test_Qid_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Stat round-trip",
         Nine_P_Proto_Tests.Test_Stat_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Tversion",
         Nine_P_Proto_Tests.Test_Tversion_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Rversion",
         Nine_P_Proto_Tests.Test_Rversion_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Tattach",
         Nine_P_Proto_Tests.Test_Tattach_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Rattach",
         Nine_P_Proto_Tests.Test_Rattach_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Rerror",
         Nine_P_Proto_Tests.Test_Rerror_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Twalk",
         Nine_P_Proto_Tests.Test_Twalk_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Rwalk",
         Nine_P_Proto_Tests.Test_Rwalk_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Topen",
         Nine_P_Proto_Tests.Test_Topen_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Ropen",
         Nine_P_Proto_Tests.Test_Ropen_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Tread",
         Nine_P_Proto_Tests.Test_Tread_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Rread",
         Nine_P_Proto_Tests.Test_Rread_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Twrite",
         Nine_P_Proto_Tests.Test_Twrite_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Twrite with empty data (count=0)",
         Nine_P_Proto_Tests.Test_Twrite_Empty_Data'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Rwrite",
         Nine_P_Proto_Tests.Test_Rwrite_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Tclunk",
         Nine_P_Proto_Tests.Test_Tclunk_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Pack/Unpack Tstat/Rstat",
         Nine_P_Proto_Tests.Test_Stat_Message_Round_Trip'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Message size field is correct",
         Nine_P_Proto_Tests.Test_Message_Size'Access));
      Result.Add_Test (Proto_Caller.Create
        ("Little-endian byte order",
         Nine_P_Proto_Tests.Test_Little_Endian'Access));
      Result.Add_Test (Proto_Caller.Create
        ("UTF-8 string encoding",
         Nine_P_Proto_Tests.Test_String_Encoding'Access));

      --  Nine_P.Client tests
      Result.Add_Test (Client_Caller.Create
        ("Namespace uses $NAMESPACE env var",
         Nine_P_Client_Tests.Test_Namespace_Uses_Env'Access));
      Result.Add_Test (Client_Caller.Create
        ("Namespace fallback to /tmp/ns.<user>.<display>",
         Nine_P_Client_Tests.Test_Namespace_Fallback'Access));
      Result.Add_Test (Client_Caller.Create
        ("Read_Message / Write_Message round-trip",
         Nine_P_Client_Tests.Test_Read_Write_Message'Access));
      Result.Add_Test (Client_Caller.Create
        ("Read_Message respects size framing",
         Nine_P_Client_Tests.Test_Read_Message_Framing'Access));

      --  Nine_P integration tests (skipped if acme not running)
      Result.Add_Test (Nine_P_Int_Caller.Create
        ("[integration] Ns_Mount acme",
         Nine_P_Integration_Tests.Test_Ns_Mount_Acme'Access));
      Result.Add_Test (Nine_P_Int_Caller.Create
        ("[integration] Read /index matches 9p",
         Nine_P_Integration_Tests.Test_Read_Acme_Index'Access));
      Result.Add_Test (Nine_P_Int_Caller.Create
        ("[integration] Open /new/ctl returns window ID",
         Nine_P_Integration_Tests.Test_Open_New_Ctl'Access));
      Result.Add_Test (Nine_P_Int_Caller.Create
        ("[integration] Client write visible via 9p",
         Nine_P_Integration_Tests.Test_Client_Matches_9p'Access));

      --  Acme.Event_Parser tests
      Result.Add_Test (Event_Parser_Caller.Create
        ("Unquoted rc token",
         Acme_Event_Parser_Tests.Test_Unquoted_Token'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Quoted rc token with spaces",
         Acme_Event_Parser_Tests.Test_Quoted_Token'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Escaped single quote in rc token",
         Acme_Event_Parser_Tests.Test_Escaped_Quote'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Parse button-2 execute event",
         Acme_Event_Parser_Tests.Test_Parse_Execute'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Parse button-3 look event",
         Acme_Event_Parser_Tests.Test_Parse_Look'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Parse event with quoted text",
         Acme_Event_Parser_Tests.Test_Parse_Quoted_Text'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Invalid lines return False",
         Acme_Event_Parser_Tests.Test_Parse_Invalid'Access));
      Result.Add_Test (Event_Parser_Caller.Create
        ("Empty/whitespace lines return False",
         Acme_Event_Parser_Tests.Test_Parse_Empty'Access));

      --  Acme.Raw_Events tests
      Result.Add_Test (Raw_Events_Caller.Create
        ("Simple execute event",
         Acme_Raw_Events_Tests.Test_Simple_Execute'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Simple look event",
         Acme_Raw_Events_Tests.Test_Simple_Look'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Keyboard insert event",
         Acme_Raw_Events_Tests.Test_Keyboard_Insert'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Multi-digit positions",
         Acme_Raw_Events_Tests.Test_Multi_Digit_Pos'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Flag 2 expansion event",
         Acme_Raw_Events_Tests.Test_Flag2_Expansion'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Flag 8 chorded arg/origin",
         Acme_Raw_Events_Tests.Test_Flag8_Chorded'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Incremental feed",
         Acme_Raw_Events_Tests.Test_Incremental_Feed'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Two events in one feed",
         Acme_Raw_Events_Tests.Test_Two_Events_One_Feed'Access));
      Result.Add_Test (Raw_Events_Caller.Create
        ("Incomplete buffer returns False",
         Acme_Raw_Events_Tests.Test_Incomplete_Returns_False'Access));

      --  Acme.Window pure tests (no live acme)
      Result.Add_Test (Window_Caller.Create
        ("Win_File_Path generates correct paths",
         Acme_Window_Tests.Test_Win_File_Path'Access));
      Result.Add_Test (Window_Caller.Create
        ("Event_Path generates correct path",
         Acme_Window_Tests.Test_Event_Path'Access));
      Result.Add_Test (Window_Caller.Create
        ("Win_File_Path id=1 has no leading space",
         Acme_Window_Tests.Test_Win_File_Path_Id1'Access));

      --  Acme.Window integration tests (skipped if acme not running)
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] New_Win has valid ID",
         Acme_Integration_Tests.Test_New_Win_Has_Valid_Id'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Append visible via 9p",
         Acme_Integration_Tests.Test_Append_Visible_Via_9p'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Set_Name reflected in ctl",
         Acme_Integration_Tests.Test_Set_Name'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Selection empty on fresh window",
         Acme_Integration_Tests.Test_Selection_Empty'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Raw event parser with live window",
         Acme_Integration_Tests.Test_Raw_Event_From_Live'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Replace_Match substitutes matched text",
         Acme_Integration_Tests.Test_Replace_Match_Simple'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Replace_Match is silent when pattern absent",
         Acme_Integration_Tests.Test_Replace_Match_No_Match'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Replace_Match closes parallel blocks independently",
         Acme_Integration_Tests.Test_Replace_Match_Parallel_Blocks'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Clear: Replace_Match ""1,$"" erases body content",
         Acme_Integration_Tests.Test_Clear_Body_Erases_Content'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Clear: full sequence leaves only the status line",
         Acme_Integration_Tests.Test_Clear_Body_Restores_Status'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Clear: safe on an already-empty body",
         Acme_Integration_Tests.Test_Clear_Body_On_Empty_Body'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Live footer: summary and fork share one line",
         Acme_Integration_Tests.Test_Append_Live_Turn_Footer'Access));
      Result.Add_Test (Acme_Int_Caller.Create
        ("[integration] Live footer: cost segments appear when non-zero",
         Acme_Integration_Tests.Test_Append_Live_Turn_Footer_With_Cost
           'Access));

      --  Pi_RPC tests
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Find_Pi returns a non-empty path",
         Pi_RPC_Tests.Test_Find_Pi_Non_Empty'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Spawn echo and read stdout",
         Pi_RPC_Tests.Test_Spawn_Echo'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Read multiple lines from stdout",
         Pi_RPC_Tests.Test_Read_Multiple_Lines'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Capture stderr line",
         Pi_RPC_Tests.Test_Stderr_Capture'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Process exits after completion",
         Pi_RPC_Tests.Test_Process_Exits'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Send lines to cat and read back",
         Pi_RPC_Tests.Test_Send_To_Cat'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Read_Line handles 1 MiB line without stack overflow",
         Pi_RPC_Tests.Test_Read_Very_Long_Line'Access));
      Result.Add_Test (Pi_RPC_Caller.Create
        ("Read_Line returns partial content at EOF without trailing newline",
         Pi_RPC_Tests.Test_Read_No_Trailing_Newline'Access));

      --  pi interface tests (github-copilot/gpt-5-mini, free tier)
      Result.Add_Test (Pi_Iface_Caller.Create
        ("[pi] get_state returns model + sessionId",
         Pi_Interface_Tests.Test_Get_State'Access));
      Result.Add_Test (Pi_Iface_Caller.Create
        ("[pi] set_model RPC returns id + contextWindow",
         Pi_Interface_Tests.Test_Model_Select_Event'Access));
      Result.Add_Test (Pi_Iface_Caller.Create
        ("[pi] simple prompt returns PONG",
         Pi_Interface_Tests.Test_Simple_Prompt'Access));
      Result.Add_Test (Pi_Iface_Caller.Create
        ("[pi] abort terminates agent_start/agent_end cycle",
         Pi_Interface_Tests.Test_Abort'Access));
      Result.Add_Test (Pi_Iface_Caller.Create
        ("[pi] message_end carries output token count",
         Pi_Interface_Tests.Test_Message_End_Tokens'Access));
      Result.Add_Test (Pi_Iface_Caller.Create
        ("[pi] Restart replaces subprocess; get_state responds",
         Pi_Interface_Tests.Test_Restart'Access));

      --  Session_Lister tests
      Result.Add_Test (Session_Lister_Caller.Create
        ("Encode_Cwd absolute path",
         Session_Lister_Tests.Test_Encode_Cwd_Absolute'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Encode_Cwd relative path",
         Session_Lister_Tests.Test_Encode_Cwd_Relative'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Encode_Cwd empty/root path",
         Session_Lister_Tests.Test_Encode_Cwd_Empty'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Format_Timestamp ISO with Z",
         Session_Lister_Tests.Test_Format_Timestamp'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Format_Timestamp short string verbatim",
         Session_Lister_Tests.Test_Format_Timestamp_Short'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Parse full session JSONL",
         Session_Lister_Tests.Test_Parse_Session_Full'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Parse session JSONL without name",
         Session_Lister_Tests.Test_Parse_Session_No_Name'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Parse session JSONL with bad JSON",
         Session_Lister_Tests.Test_Parse_Session_Bad_Json'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Parse session JSONL with a very long line (no stack overflow)",
         Session_Lister_Tests.Test_Parse_Session_Long_Line'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Find_Session_File found in test dir",
         Session_Lister_Tests.Test_Find_Session_File_Found'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Find_Session_File returns empty when UUID absent",
         Session_Lister_Tests.Test_Find_Session_File_Not_Found'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Find_Session_File searches all session subdirectories",
         Session_Lister_Tests.Test_Find_Session_File_Any_Dir'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Fork_Session forks after first turn",
         Session_Lister_Tests.Test_Fork_Session_One_Turn'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Fork_Session forks after second turn",
         Session_Lister_Tests.Test_Fork_Session_Second_Turn'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Fork_Session returns empty beyond last turn",
         Session_Lister_Tests.Test_Fork_Session_Beyond_End'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Fork_Session returns empty for missing source",
         Session_Lister_Tests.Test_Fork_Session_Missing_Src'Access));

      --  Pi_Acme_App (App_State) tests
      Result.Add_Test (App_State_Caller.Create
        ("App_State model round-trip",
         Pi_Acme_App_Tests.Test_State_Model'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State streaming flag",
         Pi_Acme_App_Tests.Test_State_Streaming'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State token counts",
         Pi_Acme_App_Tests.Test_State_Tokens'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State shutdown barrier",
         Pi_Acme_App_Tests.Test_State_Shutdown'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State session ID",
         Pi_Acme_App_Tests.Test_State_Session_Id'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Request/Consume_Reload round-trip",
         Pi_Acme_App_Tests.Test_State_Request_Consume_Reload'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Consume_Reload clears flag",
         Pi_Acme_App_Tests.Test_State_Consume_Clears_Flag'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Wait_Restart_Complete unblocks on Signal_Restart_Done",
         Pi_Acme_App_Tests.Test_State_Restart_Done'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Wait_Restart_Complete unblocks on "
         & "Signal_Restart_Aborted",
         Pi_Acme_App_Tests.Test_State_Restart_Aborted'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State two consecutive restart cycles",
         Pi_Acme_App_Tests.Test_State_Reload_Cycle'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Nth_Field basic space-separated",
         Pi_Acme_App_Tests.Test_Nth_Field_Basic'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Nth_Field tab-separated (pi --list-models format)",
         Pi_Acme_App_Tests.Test_Nth_Field_Tabs'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Nth_Field edge cases",
         Pi_Acme_App_Tests.Test_Nth_Field_Edges'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Parse_Session_Token PID match",
         Pi_Acme_App_Tests.Test_Parse_Token_Pid_Match'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Parse_Session_Token PID mismatch",
         Pi_Acme_App_Tests.Test_Parse_Token_Pid_Mismatch'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Parse_Session_Token bare token",
         Pi_Acme_App_Tests.Test_Parse_Token_Bare'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Parse_Session_Token bare token with another PID",
         Pi_Acme_App_Tests.Test_Parse_Token_Other_Pid'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Parse_Session_Token empty input",
         Pi_Acme_App_Tests.Test_Parse_Token_Empty'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Parse_Session_Token non-session token",
         Pi_Acme_App_Tests.Test_Parse_Token_Non_Token'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Turn_Count increment",
         Pi_Acme_App_Tests.Test_State_Turn_Count_Increment'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Turn_Count set",
         Pi_Acme_App_Tests.Test_State_Turn_Count_Set'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Turn_Count reset",
         Pi_Acme_App_Tests.Test_State_Turn_Count_Reset'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Is_Retrying initial value is False",
         Pi_Acme_App_Tests.Test_State_Is_Retrying_Initial'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Is_Retrying set and clear",
         Pi_Acme_App_Tests.Test_State_Is_Retrying_Set_And_Clear'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Is_Retrying independent of text flags",
         Pi_Acme_App_Tests.Test_State_Is_Retrying_Independent'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Has_Text_Delta initial value is False",
         Pi_Acme_App_Tests.Test_State_Has_Text_Delta_Initial'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Has_Text_Delta set and clear",
         Pi_Acme_App_Tests.Test_State_Has_Text_Delta_Set_And_Clear'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Has_Text_Delta independent of Text_Emitted",
         Pi_Acme_App_Tests.Test_State_Has_Text_Delta_Independent'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Pending_Stats gated by Has_Text_Delta",
         Pi_Acme_App_Tests.Test_State_Pending_Stats_Gated_By_Text_Delta
           'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: identical texts return (no changes)",
         Pi_Acme_App_Tests.Test_Edit_Diff_No_Change'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: changed line shows - and + lines",
         Pi_Acme_App_Tests.Test_Edit_Diff_Single_Substitution'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: added lines appear as + lines",
         Pi_Acme_App_Tests.Test_Edit_Diff_Added_Lines'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: removed lines appear as - lines",
         Pi_Acme_App_Tests.Test_Edit_Diff_Removed_Lines'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: output contains no ---/+++/@@ headers",
         Pi_Acme_App_Tests.Test_Edit_Diff_No_Headers'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: diff > Max_L lines is truncated with trailer",
         Pi_Acme_App_Tests.Test_Edit_Diff_Truncation'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: UTF-8 bytes in context lines preserved",
         Pi_Acme_App_Tests.Test_Edit_Diff_Utf8_Context_Line'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: UTF-8 bytes in removed lines preserved",
         Pi_Acme_App_Tests.Test_Edit_Diff_Utf8_Removed_Line'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: UTF-8 bytes in added lines preserved",
         Pi_Acme_App_Tests.Test_Edit_Diff_Utf8_Added_Line'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Edit_Diff_Lines: no double-encoding under -gnatW8 (regression)",
         Pi_Acme_App_Tests.Test_Edit_Diff_No_Double_Encoding'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Stats model part: non-empty when model is set",
         Pi_Acme_App_Tests.Test_Stats_Model_Part_When_Set'Access));
      Result.Add_Test (App_State_Caller.Create
        ("Stats model part: empty guard when no model set",
         Pi_Acme_App_Tests.Test_Stats_Model_Part_When_Empty'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Turn_Cost_Dmil initial value is 0",
         Pi_Acme_App_Tests.Test_State_Turn_Cost_Initial'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Turn_Cost_Dmil round-trip via Set_Turn_Cost",
         Pi_Acme_App_Tests.Test_State_Turn_Cost_Round_Trip'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State session stats fields all start at 0",
         Pi_Acme_App_Tests.Test_State_Session_Stats_Initial'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Set_Session_Stats stores all six fields atomically",
         Pi_Acme_App_Tests.Test_State_Session_Stats_Round_Trip'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State Set_Session_Stats with zeros resets all fields",
         Pi_Acme_App_Tests.Test_State_Session_Stats_Reset'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State cost fields are independent of per-turn token counts",
         Pi_Acme_App_Tests.Test_State_Cost_Independent_Of_Tokens'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: string value returned without quotes",
         Pi_Acme_App_Tests.Test_JSON_Scalar_String'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: integer value serialised as numeric string",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Integer'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: negative integer serialised correctly",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Negative_Integer'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: boolean true serialises to ""true""",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Boolean_True'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: boolean false serialises to ""false""",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Boolean_False'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: float value serialises to non-empty string",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Float'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: null value returns ""...""",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Null'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: object value returns ""...""",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Object'Access));
      Result.Add_Test (App_State_Caller.Create
        ("JSON_Scalar_Image: array value returns ""...""",
         Pi_Acme_App_Tests.Test_JSON_Scalar_Array'Access));

      Result.Add_Test (App_State_Caller.Create
        ("App_State One_Shot_Result initial value is empty",
         Pi_Acme_App_Tests.Test_One_Shot_Result_Initial'Access));
      Result.Add_Test (App_State_Caller.Create
        ("App_State One_Shot_Result first-write-wins",
         Pi_Acme_App_Tests.Test_One_Shot_Result_First_Write_Wins'Access));

      --  Session_History integration tests (require live acme)
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: file not found writes error",
         Session_History_Tests.Test_Render_File_Not_Found'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: user message rendered as triangle text",
         Session_History_Tests.Test_Render_User_Message'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: assistant text rendered verbatim",
         Session_History_Tests.Test_Render_Assistant_Text'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: successful tool call shows check mark",
         Session_History_Tests.Test_Render_Tool_Call_Success'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: failed tool call shows cross mark",
         Session_History_Tests.Test_Render_Tool_Call_Error'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: thinking block prefixed with bar",
         Session_History_Tests.Test_Render_Thinking_Block'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: model_change writes [Model ...] line",
         Session_History_Tests.Test_Render_Model_Change'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: token usage updates State.Turn_Tokens",
         Session_History_Tests.Test_Render_Token_Stats'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: separator appended after history",
         Session_History_Tests.Test_Render_Separator'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: tool call header contains llm-chat+ URI",
         Session_History_Tests.Test_Render_Tool_Call_URI'Access));
      Result.Add_Test (Session_History_Caller.Create
        ("[integration] Render: tool call header has no URI when id absent",
         Session_History_Tests.Test_Render_Tool_Call_No_URI'Access));

      --  Tool_URI unit tests (pure, no acme required)
      Result.Add_Test (Tool_URI_Caller.Create
        ("Hash_Tool_Id: SHA-256 of empty string",
         Tool_URI_Tests.Test_Hash_Empty'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Hash_Tool_Id: known values match Python reference",
         Tool_URI_Tests.Test_Hash_Known_Values'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Hash_Tool_Id: result is always 16 characters",
         Tool_URI_Tests.Test_Hash_Length'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Hash_Tool_Id: distinct inputs produce distinct hashes",
         Tool_URI_Tests.Test_Hash_Distinct'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Hash_Tool_Id: result contains only lowercase hex",
         Tool_URI_Tests.Test_Hash_Lowercase_Hex'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: token at context start",
         Tool_URI_Tests.Test_Scan_Token_At_Start'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: token at context end",
         Tool_URI_Tests.Test_Scan_Token_At_End'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: token in middle of context",
         Tool_URI_Tests.Test_Scan_Token_In_Middle'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: anchor at first character of token",
         Tool_URI_Tests.Test_Scan_Anchor_At_Token_Start'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: anchor at last character of token",
         Tool_URI_Tests.Test_Scan_Anchor_At_Token_End'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: anchor one position before token",
         Tool_URI_Tests.Test_Scan_Anchor_Before_Token'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: anchor one position after token",
         Tool_URI_Tests.Test_Scan_Anchor_After_Token'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: empty context",
         Tool_URI_Tests.Test_Scan_Empty_Context'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: context with no token",
         Tool_URI_Tests.Test_Scan_No_Token'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: token missing /tool/ separator",
         Tool_URI_Tests.Test_Scan_No_Tool_Separator'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: empty hex suffix after /tool/",
         Tool_URI_Tests.Test_Scan_Empty_Hex_Suffix'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: empty UUID part",
         Tool_URI_Tests.Test_Scan_Empty_Uuid'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: non-zero Ctx_Start shifts positions",
         Tool_URI_Tests.Test_Scan_Nonzero_Ctx_Start'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Tool_Token: anchor in second of two tokens",
         Tool_URI_Tests.Test_Scan_Second_Of_Two'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: anchor in fork token",
         Tool_URI_Tests.Test_Scan_Fork_Basic'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: anchor before token",
         Tool_URI_Tests.Test_Scan_Fork_Before'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: anchor after token",
         Tool_URI_Tests.Test_Scan_Fork_After'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: empty context",
         Tool_URI_Tests.Test_Scan_Fork_Empty'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: non-zero Ctx_Start",
         Tool_URI_Tests.Test_Scan_Fork_Ctx_Start'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: missing UUID",
         Tool_URI_Tests.Test_Scan_Fork_No_Uuid'Access));
      Result.Add_Test (Tool_URI_Caller.Create
        ("Scan_Fork_Token: missing turn number",
         Tool_URI_Tests.Test_Scan_Fork_No_Turn'Access));

      --  Subagent (--one-shot) integration tests (require live acme)
      Result.Add_Test (Subagent_Int_Caller.Create
        ("[subagent] One-shot returns JSON with output and session_id",
         Subagent_Integration_Tests.Test_One_Shot_Returns_Json'Access));
      Result.Add_Test (Subagent_Int_Caller.Create
        ("[subagent] Two --one-shot runs use distinct sessions",
         Subagent_Integration_Tests
           .Test_One_Shot_Fresh_Session_Each_Run'Access));

      return Result;
   end Suite;

end Test_Suites;
