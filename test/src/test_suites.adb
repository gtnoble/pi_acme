with AUnit.Test_Suites;
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
        ("Find_Session_File found in test dir",
         Session_Lister_Tests.Test_Find_Session_File_Found'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Find_Session_File returns empty when UUID absent",
         Session_Lister_Tests.Test_Find_Session_File_Not_Found'Access));
      Result.Add_Test (Session_Lister_Caller.Create
        ("Find_Session_File searches all session subdirectories",
         Session_Lister_Tests.Test_Find_Session_File_Any_Dir'Access));

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

      return Result;
   end Suite;

end Test_Suites;
