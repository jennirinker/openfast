!**********************************************************************************************************************************
! LICENSING
! Copyright (C) 2015-2016  National Renewable Energy Laboratory
! Copyright (C) 2016-2017  Envision Energy USA, LTD       
!   
!    This file is part of the NWTC Subroutine Library.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
!**********************************************************************************************************************************
PROGRAM BeamDyn_Driver_Program

   USE BeamDyn_driver_subs  ! all other modules inherited through this one

   IMPLICIT NONE

   ! global glue-code-specific variables

   INTEGER(IntKi)                   :: ErrStat          ! Error status of the operation
   CHARACTER(1024)                  :: ErrMsg           ! Error message if ErrStat /= ErrID_None
   REAL(DbKi)                       :: dt_global        ! fixed/constant global time step
   REAL(DbKi)                       :: t_global         ! global-loop time marker
   INTEGER(IntKi)                   :: n_t_final        ! total number of time steps
   INTEGER(IntKi)                   :: n_t_global       ! global-loop time counter
   INTEGER(IntKi), parameter        :: BD_interp_order = 1  ! order of interpolation/extrapolation

   ! Module1 Derived-types variables; see Registry_Module1.txt for details

   TYPE(BD_InitInputType)           :: BD_InitInput
   TYPE(BD_ParameterType)           :: BD_Parameter
   TYPE(BD_ContinuousStateType)     :: BD_ContinuousState
   TYPE(BD_InitOutputType)          :: BD_InitOutput
   TYPE(BD_DiscreteStateType)       :: BD_DiscreteState
   TYPE(BD_ConstraintStateType)     :: BD_ConstraintState
   TYPE(BD_OtherStateType)          :: BD_OtherState
   TYPE(BD_MiscVarType)             :: BD_MiscVar
   TYPE(BD_InputType) ,ALLOCATABLE  :: BD_Input(:)
   REAL(DbKi),         ALLOCATABLE  :: BD_InputTimes(:)
   TYPE(BD_OutputType)              :: BD_Output
   INTEGER(IntKi)                   :: DvrOut 
   
   TYPE(BD_DriverInternalType)      :: DvrData

   CHARACTER(256)                   :: DvrInputFile
   CHARACTER(256)                   :: RootName


   ! local variables
   Integer(IntKi)                          :: j               ! counter for various loops
   Integer(IntKi)                          :: i               ! counter for various loops
   
    REAL(DbKi)  :: TiLstPrn      !< The simulation time of the last print (to file) [(s)]
    REAL(ReKi)  :: PrevClockTime      !< Clock time at start of simulation in seconds [(s)]
    REAL(ReKi)  :: UsrTime1      !< User CPU time for simulation initialization [(s)]
    REAL(ReKi)  :: UsrTime2      !< User CPU time for simulation (without intialization) [(s)]
    INTEGER(IntKi) , DIMENSION(1:8)  :: StrtTime      !< Start time of simulation (including intialization) [-]
    INTEGER(IntKi) , DIMENSION(1:8)  :: SimStrtTime      !< Start time of simulation (after initialization) [-]
   

   
   TYPE(ProgDesc), PARAMETER   :: version   = ProgDesc( 'BeamDyn Driver', 'v2.00.00', '9-May-2017' )  ! The version number of this program.
   

   ! -------------------------------------------------------------------------
   ! Initialization of library (especially for screen output)
   ! -------------------------------------------------------------------------  
   
   CALL DATE_AND_TIME ( Values=StrtTime )                 ! Let's time the whole simulation
   CALL CPU_TIME ( UsrTime1 )                             ! Initial time (this zeros the start time when used as a MATLAB function)
   UsrTime1 = MAX( 0.0_ReKi, UsrTime1 )                   ! CPU_TIME: If a meaningful time cannot be returned, a processor-dependent negative value is returned

   
   CALL NWTC_Init()
      ! Display the copyright notice
   CALL DispCopyrightLicense( version )   
      ! Tell our users what they're running
   CALL WrScr( ' Running '//GetNVD( version )//NewLine//' linked with '//TRIM( GetNVD( NWTC_Ver ))//NewLine )
   
   ! -------------------------------------------------------------------------
   ! Initialization of glue-code time-step variables
   ! -------------------------------------------------------------------------   
   
   CALL GET_COMMAND_ARGUMENT(1,DvrInputFile)
   CALL GetRoot(DvrInputFile,RootName)
   CALL BD_ReadDvrFile(DvrInputFile,dt_global,BD_InitInput,DvrData,ErrStat,ErrMsg)
      CALL CheckError()
      
      ! initialize the BD_InitInput values not in the driver input file
   BD_InitInput%RootName = TRIM(BD_Initinput%InputFile)
   BD_InitInput%RootDisp = 0.0_R8Ki
   BD_InitInput%RootOri  = BD_InitInput%GlbRot
   
   t_global = DvrData%t_initial
   n_t_final = ((DvrData%t_final - DvrData%t_initial) / dt_global )

   !Module1: allocate Input and Output arrays; used for interpolation and extrapolation
   ALLOCATE(BD_Input(BD_interp_order + 1)) 
   ALLOCATE(BD_InputTimes(BD_interp_order + 1)) 

   CALL BD_Init(BD_InitInput             &
                   , BD_Input(1)         &
                   , BD_Parameter        &
                   , BD_ContinuousState  &
                   , BD_DiscreteState    &
                   , BD_ConstraintState  &
                   , BD_OtherState       &
                   , BD_Output           &
                   , BD_MiscVar          &
                   , dt_global           &
                   , BD_InitOutput       &
                   , ErrStat             &
                   , ErrMsg )
      CALL CheckError()
   
   call Init_RotationCenterMesh(DvrData, BD_InitInput, BD_Input(1)%RootMotion, ErrStat, ErrMsg)
      CALL CheckError()

   call CreateMultiPointMeshes(DvrData,BD_InitOutput,BD_Parameter, BD_Output, BD_Input(1), ErrStat, ErrMsg)   
   call Transfer_MultipointLoads(DvrData, BD_Output, BD_Input(1), ErrStat, ErrMsg)   
   
   CALL Dvr_InitializeOutputFile(DvrOut,BD_InitOutput,RootName,ErrStat,ErrMsg)
      CALL CheckError()
      
      
      ! initialize BD_Input and BD_InputTimes
   BD_InputTimes(1) = DvrData%t_initial
   CALL BD_InputSolve( BD_InputTimes(1), BD_Input(1), DvrData, ErrStat, ErrMsg)
   
   DO j = 2,BD_interp_order+1
         ! create new meshes
      CALL BD_CopyInput (BD_Input(1) , BD_Input(j) , MESH_NEWCOPY, ErrStat, ErrMsg)
         CALL CheckError()
         
         ! solve for inputs at previous time steps
      BD_InputTimes(j) = DvrData%t_initial - (j - 1) * dt_global
      CALL BD_InputSolve( BD_InputTimes(j), BD_Input(j), DvrData, ErrStat, ErrMsg)
         CALL CheckError()
   END DO
   


      !.........................
      ! calculate outputs at t=0
      !.........................
   CALL SimStatus_FirstTime( TiLstPrn, PrevClockTime, SimStrtTime, UsrTime2, t_global, DvrData%t_final )
    
    
   CALL BD_CalcOutput( t_global, BD_Input(1), BD_Parameter, BD_ContinuousState, BD_DiscreteState, &
                           BD_ConstraintState, BD_OtherState,  BD_Output, BD_MiscVar, ErrStat, ErrMsg)
      CALL CheckError()
   
     CALL Dvr_WriteOutputLine(t_global,DvrOut,BD_Parameter%OutFmt,BD_Output)
   
      !.........................
      ! time marching
      !.........................
     
   DO n_t_global = 0, n_t_final
      

      ! Shift "window" of BD_Input 
  
      DO j = BD_interp_order, 1, -1
         CALL BD_CopyInput (BD_Input(j),  BD_Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL CheckError()
         BD_InputTimes(j+1) = BD_InputTimes(j)
      END DO
      
      BD_InputTimes(1)  = t_global + dt_global
      CALL BD_InputSolve( BD_InputTimes(1), BD_Input(1), DvrData, ErrStat, ErrMsg)
         CALL CheckError()
      
                       
     IF(BD_Parameter%analysis_type .EQ. BD_STATIC_ANALYSIS .AND. n_t_global > 8) EXIT 

      ! update states from n_t_global to n_t_global + 1
     CALL BD_UpdateStates( t_global, n_t_global, BD_Input, BD_InputTimes, BD_Parameter, &
                               BD_ContinuousState, &
                               BD_DiscreteState, BD_ConstraintState, &
                               BD_OtherState, BD_MiscVar, ErrStat, ErrMsg )
        CALL CheckError()

        
      ! advance time
     t_global = (n_t_global+1) * dt_global + DvrData%t_initial
           
      ! calculate outputs at n_t_global + 1
     CALL BD_CalcOutput( t_global, BD_Input(1), BD_Parameter, BD_ContinuousState, BD_DiscreteState, &
                             BD_ConstraintState, BD_OtherState,  BD_Output, BD_MiscVar, ErrStat, ErrMsg)
        CALL CheckError()

     CALL Dvr_WriteOutputLine(t_global,DvrOut,BD_Parameter%OutFmt,BD_Output)
                
     if ( MOD( n_t_global + 1, 100 ) == 0 ) call SimStatus( TiLstPrn, PrevClockTime, t_global, DvrData%t_final )
   ENDDO
      
   CALL RunTimes( StrtTime, UsrTime1, SimStrtTime, UsrTime2, t_global )

   
   CALL Dvr_End()

CONTAINS
!----------------------------------------------------------------------------------------------------------------------------------
   SUBROUTINE Dvr_End()

      character(ErrMsgLen)                          :: errMsg2                 ! temporary Error message if ErrStat /=
      integer(IntKi)                                :: errStat2                ! temporary Error status of the operation
      character(*), parameter                       :: RoutineName = 'Dvr_End'

      IF(DvrOut >0) CLOSE(DvrOut)

      IF ( ALLOCATED(BD_Input) ) THEN
         CALL BD_End( BD_Input(1), BD_Parameter, BD_ContinuousState, BD_DiscreteState, &
               BD_ConstraintState, BD_OtherState, BD_Output, BD_MiscVar, ErrStat2, ErrMsg2 )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      
         DO i=2,BD_interp_order + 1
            CALL BD_DestroyInput( BD_Input(i), ErrStat2, ErrMsg2 )
            call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
         ENDDO
         
         DEALLOCATE(BD_Input)
      END IF

      IF(ALLOCATED(BD_InputTimes )) DEALLOCATE(BD_InputTimes )
      if(allocated(DvrData%MultiPointLoad)) deallocate(DvrData%MultiPointLoad)

      
      
      if (ErrStat >= AbortErrLev) then      
         CALL ProgAbort( 'BeamDyn Driver encountered simulation error level: '&
             //TRIM(GetErrStr(ErrStat)), TrapErrors=.FALSE., TimeWait=3._ReKi )  ! wait 3 seconds (in case they double-clicked and got an error)
      else
         call NormStop()
      end if
   END SUBROUTINE Dvr_End
!----------------------------------------------------------------------------------------------------------------------------------
   subroutine CheckError()
   
      if (ErrStat /= ErrID_None) then
         call WrScr(TRIM(ErrMsg))
         
         if (ErrStat >= AbortErrLev) then
            call Dvr_End()
         end if
      end if
         
   end subroutine CheckError
!----------------------------------------------------------------------------------------------------------------------------------
   subroutine CreateMultiPointMeshes()
   
   ! DvrData%NumPointLoads is at least 1
   
   !.......................
   ! Mesh for multi-point loading on blades
   !.......................
   CALL MeshCreate( BlankMesh        = DvrData%mplMotion  &
                   ,IOS              = COMPONENT_INPUT    &
                   ,NNodes           = DvrData%NumPointLoads      &
                   ,TranslationDisp  = .TRUE.             &
                   ,Orientation      = .TRUE.             &
                   ,TranslationVel   = .TRUE.             &
                   ,RotationVel      = .TRUE.             &
                   ,TranslationAcc   = .TRUE.             &
                   ,RotationAcc      = .TRUE.             &
                   ,ErrStat          = ErrStat2           &
                   ,ErrMess          = ErrMsg2             )
      CALL SetErrStat( ErrStat2, ErrMsg2, ErrStat, ErrMsg, RoutineName )
      
      ! these nodes are placed along the key point line (as are the GLL nodes)
   DO i = 1,DvrData%NumPointLoads

       call Find_IniNode(BD_InitOutput%kp_coordinate, BD_Parameter, 1, BD_InitOutput%kp_total, DvrData%MultiPointLoad(i,1), temp_POS, temp_CRV)
       
       Pos = BD_Parameter%GlbPos + MATMUL(BD_Parameter%GlbRot,temp_POS)
       
       temp_CRV2 = MATMUL(BD_Parameter%GlbRot,temp_CRV)
       CALL BD_CrvCompose(temp_CRV,BD_Parameter%Glb_crv,temp_CRV2,FLAG_R1R2) !temp_CRV = p%Glb_crv composed with temp_CRV2

END PROGRAM BeamDyn_Driver_Program
