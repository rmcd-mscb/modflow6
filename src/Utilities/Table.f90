! Comprehensive table object that stores all of the 
! intercell flows, and the inflows and the outflows for 
! an advanced package.
module TableModule
  
  use KindModule, only: I4B, DP
  use ConstantsModule, only: LINELENGTH, LENBUDTXT,                              &
                             TABSTRING, TABUCSTRING, TABINTEGER, TABREAL
  use TableTermModule, only: TableTermType
  use InputOutputModule, only: UWWORD, parseline
  use SimModule, only: store_error, ustop
  use TdisModule, only: kstp, kper
  
  implicit none
  
  public :: TableType
  public :: table_cr
  
  type :: TableType
    !
    ! -- name, number of control volumes, and number of table terms
    character(len=LENBUDTXT) :: name
    character(len=LINELENGTH) :: title
    logical, pointer :: first_entry => null()
    logical, pointer :: transient => null()
    integer(I4B), pointer :: iout => null()
    integer(I4B), pointer :: maxbound => null()
    integer(I4B), pointer :: nheaderlines => null()
    integer(I4B), pointer :: nlinewidth => null()
    integer(I4B), pointer :: ntableterm => null()
    integer(I4B), pointer :: ientry => null()
    integer(I4B), pointer :: iloc => null()
    integer(I4B), pointer :: icount => null()
    integer(I4B), pointer :: kstp => null()
    integer(I4B), pointer :: kper => null()
    !
    ! -- array of table terms, with one separate entry for each term
    !    such as rainfall, et, leakage, etc.
    type(TableTermType), dimension(:), pointer :: tableterm => null()
    !
    ! -- table table object, for writing the typical MODFLOW table
    type(TableType), pointer :: table => null()
    
    character(len=LINELENGTH), pointer :: linesep => null()
    character(len=LINELENGTH), pointer :: dataline => null()
    character(len=LINELENGTH), dimension(:), pointer :: header => null()
    
    contains
  
    procedure :: table_df
    procedure :: table_da
    procedure :: initialize_column
    procedure :: line_to_columns
    procedure :: finalize_table  
    procedure :: set_maxbound
    procedure :: set_title
    procedure :: print_list_entry

    procedure, private :: allocate_strings
    procedure, private :: set_header  
    procedure, private :: write_header 
    procedure, private :: write_line  
    procedure, private :: finalize
    procedure, private :: add_error
    procedure, private :: reset
    
    generic, public :: add_term => add_integer, add_real, add_string
    procedure, private :: add_integer, add_real, add_string    

  end type TableType
  
  contains

  subroutine table_cr(this, name, title)
! ******************************************************************************
! table_cr -- Create a new table object
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    type(TableType), pointer :: this
    character(len=*), intent(in) :: name
    character(len=*), intent(in) :: title
    ! -- local
! ------------------------------------------------------------------------------
    !
    ! -- check if table already associated and reset if necessary
    if (associated(this)) then
      call this%table_da()
      deallocate(this)
      nullify(this)
    end if
    !
    ! -- Create the object
    allocate(this)
    !
    ! -- initialize variables
    this%name = name
    this%title = title
    !
    ! -- Return
    return
  end subroutine table_cr

  subroutine table_df(this, maxbound, ntableterm, iout, transient)
! ******************************************************************************
! table_df -- Define the new table object
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    integer(I4B), intent(in) :: maxbound
    integer(I4B), intent(in) :: ntableterm
    integer(I4B), intent(in) :: iout
    logical, intent(in), optional :: transient
! ------------------------------------------------------------------------------
    !
    ! -- allocate scalars
    allocate(this%transient)
    allocate(this%first_entry)
    allocate(this%iout)
    allocate(this%maxbound)
    allocate(this%nheaderlines)
    allocate(this%nlinewidth)
    allocate(this%ntableterm)
    allocate(this%ientry)
    allocate(this%iloc)
    allocate(this%icount)
    !
    ! -- allocate space for tableterm
    allocate(this%tableterm(ntableterm))
    !
    ! -- initialize values
    if (present(transient)) then
      this%transient = transient
    else
      this%transient = .FALSE.
    end if
    this%first_entry = .TRUE.
    this%iout = iout
    this%maxbound = maxbound
    this%ntableterm = ntableterm
    this%ientry = 0
    this%icount = 0
    !
    ! -- return
    return
  end subroutine table_df
  
  subroutine initialize_column(this, text, width, alignment)
! ******************************************************************************
! initialize_column -- Initialize data for a column
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    character(len=*), intent(in) :: text
    integer(I4B), intent(in) :: width
    integer(I4B), intent(in) :: alignment
    ! -- local
    character (len=LINELENGTH) :: errmsg
    integer(I4B) :: idx
! ------------------------------------------------------------------------------
    !
    ! -- update index for tableterm
    this%ientry = this%ientry + 1
    idx = this%ientry
    !
    ! -- check that ientry is in bounds
    if (this%ientry > this%ntableterm) then
      write(errmsg,'(4x,a,a,a,i0,a,1x,a,1x,a,a,a,1x,i0,1x,a)')                   &
        '****ERROR. TRYING TO ADD COLUMN "', trim(adjustl(text)), '" (',         &
        this%ientry, ') IN THE', trim(adjustl(this%name)), 'TABLE ("',           &
        trim(adjustl(this%title)), '") THAT ONLY HAS', this%ntableterm, 'COLUMNS'
      call store_error(errmsg)
      call ustop()
    end if
    !
    ! -- initialize table term
    call this%tableterm(idx)%initialize(text, width, alignment=alignment)      
    !
    ! -- create header when all terms have been specified
    if (this%ientry == this%ntableterm) then
      call this%set_header()
      !
      ! -- reset ientry
      this%ientry = 0
    end if
    !
    ! -- return
    return
  end subroutine initialize_column
  
  subroutine set_header(this)
! ******************************************************************************
! set_header -- Set the table object header
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
    character(len=LINELENGTH) :: cval
    integer(I4B) :: width
    integer(I4B) :: alignment
    integer(I4B) :: nlines
    integer(I4B) :: iloc
    integer(I4B) :: ival
    real(DP) :: rval
    integer(I4B) :: j
    integer(I4B) :: n
! ------------------------------------------------------------------------------
    !
    ! -- initialize variables
    width = 0
    nlines = 0
    !
    ! -- determine total width and maximum number of lines
    do n = 1, this%ntableterm
      width = width + this%tableterm(n)%get_width()
      nlines = max(nlines, this%tableterm(n)%get_header_lines())
    end do
    !
    ! -- add length of separators
    width = width + this%ntableterm - 1
    !
    ! -- allocate the header and line separator
    call this%allocate_strings(width, nlines)
    !
    ! -- build final header lines
    do n = 1, this%ntableterm
      call this%tableterm(n)%set_header(nlines)
    end do
    !
    ! -- build header
    do n = 1, nlines
      iloc = 1
      this%iloc = 1
      do j = 1, this%ntableterm
        width = this%tableterm(j)%get_width()
        alignment = this%tableterm(j)%get_alignment()
        call this%tableterm(j)%get_header(n, cval)
        if (j == this%ntableterm) then
          call UWWORD(this%header(n+1), iloc, width, TABUCSTRING,                &
                      cval(1:width), ival, rval, ALIGNMENT=alignment)
        else
          call UWWORD(this%header(n+1), iloc, width, TABUCSTRING,                &
                      cval(1:width), ival, rval, ALIGNMENT=alignment, SEP=' ')
        end if
      end do
    end do
    !
    ! -- return
    return
  end subroutine set_header
  
  subroutine allocate_strings(this, width, nlines)
! ******************************************************************************
! allocate_header -- Allocate deferred length strings
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    integer(I4B), intent(in) :: width
    integer(I4B), intent(in) :: nlines
    ! -- local
    character(len=width) :: string
    character(len=width) :: linesep
    integer(I4B) :: n
! ------------------------------------------------------------------------------
    !
    ! -- initialize local variables
    string = ''
    linesep = repeat('-', width)
    !
    ! -- initialize variables
    this%nheaderlines = nlines + 2
    this%nlinewidth = width
    !
    ! -- allocate deferred length strings
    allocate(this%header(this%nheaderlines))
    allocate(this%linesep)
    allocate(this%dataline)
    !
    ! -- initialize lines
    this%linesep = linesep(1:width)
    this%dataline = string(1:width)
    do n = 1, this%nheaderlines
      this%header(n) = string(1:width)
    end do
    !
    ! -- fill first and last header line with
    !    linesep
    this%header(1) = linesep(1:width)
    this%header(nlines+2) = linesep(1:width)
    !
    ! -- return
    return
  end subroutine allocate_strings  

  subroutine write_header(this)
! ******************************************************************************
! write_table -- Write the table header
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
    character(len=LINELENGTH) :: title
    integer(I4B) :: width
    integer(I4B) :: n
! ------------------------------------------------------------------------------
    !
    ! -- initialize local variables
    width = this%nlinewidth
    !
    ! -- write the table header
    if (this%first_entry) then
      ! -- write title
      title = this%title
      if (this%transient) then
        write(title, '(a,a,i6)') trim(adjustl(title)), '   PERIOD ', kper
        write(title, '(a,a,i8)') trim(adjustl(title)), '   STEP ', kstp
      end if
      write(this%iout, '(/,1x,a)') trim(adjustl(title))
      !
      ! -- write header
      do n = 1, this%nheaderlines
        write(this%iout, '(1x,a)') this%header(n)(1:width)
      end do
    end if
    !
    ! -- reinitialize variables
    this%first_entry = .FALSE.
    this%ientry = 0
    this%icount = 0
    !
    ! -- return
    return
  end subroutine write_header
  
  subroutine write_line(this)
! ******************************************************************************
! write_line -- Write the data line
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
    integer(I4B) :: width
! ------------------------------------------------------------------------------
    !
    ! -- initialize local variables
    width = this%nlinewidth
    !
    ! -- write the dataline
    write(this%iout, '(1x,a)') this%dataline(1:width)
    !
    ! -- update column and line counters
    this%ientry = 0
    this%iloc = 1
    this%icount = this%icount + 1
    !
    ! -- return
    return
  end subroutine write_line
  
  subroutine finalize(this)
! ******************************************************************************
! finalize -- Private method that test for last line. If last line the
!             public finalize_table method is called  
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
! ------------------------------------------------------------------------------
    !
    ! -- finalize table if last entry
    if (this%icount == this%maxbound) then
      call this%finalize_table()
    end if
    !
    ! -- return
    return
  end subroutine finalize
  
  subroutine finalize_table(this)
! ******************************************************************************
! finalize -- Public method to finalize the table
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
    integer(I4B) :: width
! ------------------------------------------------------------------------------
    !
    ! -- initialize local variables
    width = this%nlinewidth
    !
    ! -- write the final table seperator
    write(this%iout, '(1x,a,/)') this%linesep(1:width)
    !
    ! -- reinitialize variables
    call this%reset()
    !this%ientry = 0
    !this%icount = 0
    !this%first_entry = .TRUE.
    !
    ! -- return
    return
  end subroutine finalize_table  

  subroutine table_da(this)
! ******************************************************************************
! table_da -- deallocate
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- dummy
    integer(I4B) :: i
! ------------------------------------------------------------------------------
    !
    ! -- deallocate each table term
    do i = 1, this%ntableterm
      call this%tableterm(i)%da()
    end do
    !
    ! -- deallocate space for tableterm
    deallocate(this%tableterm)
    !
    ! -- deallocate scalars
    deallocate(this%transient)
    deallocate(this%first_entry)
    deallocate(this%iout)
    deallocate(this%maxbound)
    deallocate(this%nheaderlines)
    deallocate(this%nlinewidth)
    deallocate(this%ntableterm)
    deallocate(this%ientry)
    deallocate(this%iloc)
    deallocate(this%icount)
    !
    ! -- Return
    return
  end subroutine table_da
  
  subroutine line_to_columns(this, line, finalize)
! ******************************************************************************
! line_to_columns -- convert a line to the correct number of columns
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    character(len=LINELENGTH), intent(in) :: line
    logical, intent(in), optional :: finalize
    ! -- local
    character(len=LINELENGTH), allocatable, dimension(:) :: words
    logical :: allow_finalization
    integer(I4B) :: nwords
    integer(I4B) :: icols
    integer(I4B) :: i
! ------------------------------------------------------------------------------
    !
    ! -- initialize optional variables
    if (present(finalize)) then
      allow_finalization = finalize
    else
      allow_finalization = .TRUE.
    end if
    !
    ! -- write header
    if (this%icount == 0 .and. this%ientry == 0) then
      call this%write_header()
    end if
    !
    ! -- parse line into words
    call parseline(line, nwords, words, 0)
    !
    ! -- calculate the number of entries in line but
    !    limit it to the maximum number of columns if
    !    the number of words exceeds ntableterm
    icols = this%ntableterm
    icols = min(nwords, icols)
    !
    ! -- add data (as strings) to line
    do i = 1, icols
      call this%add_term(words(i), finalize=allow_finalization)
    end do
    !
    ! -- add empty strings to complete the line
    do i = this%ientry + 1, this%ntableterm
      call this%add_term(' ', finalize=allow_finalization)
    end do
    !
    ! -- clean up local allocatable array
    deallocate(words)
    !
    ! -- Return
    return
  end subroutine line_to_columns  
  
  subroutine add_error(this)
! ******************************************************************************
! add_error -- evaluate if error condition occurs when adding data to dataline
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
    character (len=LINELENGTH) :: errmsg
! ------------------------------------------------------------------------------
    !
    ! -- check that ientry is within bounds
    if (this%ientry > this%ntableterm) then
      write(errmsg,'(4x,a,1x,i0,5(1x,a),1x,i0,1x,a)')                            &
        '****ERROR. TRYING TO ADD DATA TO COLUMN ', this%ientry, 'IN THE',       &
        trim(adjustl(this%name)), 'TABLE (', trim(adjustl(this%title)),          &
        ') THAT ONLY HAS', this%ntableterm, 'COLUMNS'
      call store_error(errmsg)
      call ustop()
    end if
    !
    ! -- Return
    return
  end subroutine add_error
  
  subroutine add_integer(this, ival, finalize)
! ******************************************************************************
! add_integer -- add integer value to the dataline
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    integer(I4B), intent(in) :: ival
    logical, intent(in), optional :: finalize
    ! -- local
    logical :: allow_finalization
    logical :: line_end
    character(len=LINELENGTH) :: cval
    real(DP) :: rval
    integer(I4B) :: width
    integer(I4B) :: alignment
    integer(I4B) :: j
! ------------------------------------------------------------------------------
    !
    ! -- initialize optional variables
    if (present(finalize)) then
      allow_finalization = finalize
    else
      allow_finalization = .TRUE.
    end if
    !
    ! -- write header
    if (this%icount == 0 .and. this%ientry == 0) then
      call this%write_header()
    end if
    !
    ! -- update index for tableterm
    this%ientry = this%ientry + 1
    !
    ! -- check that ientry is within bounds
    call this%add_error()
    !
    ! -- initialize local variables
    j = this%ientry
    width = this%tableterm(j)%get_width()
    alignment = this%tableterm(j)%get_alignment()
    line_end = .FALSE.
    !
    ! -- add data to line
    if (j == this%ntableterm) then
      line_end = .TRUE.
      call UWWORD(this%dataline, this%iloc, width, TABINTEGER,                   &
                  cval, ival, rval, ALIGNMENT=alignment)
    else
      call UWWORD(this%dataline, this%iloc, width, TABINTEGER,                   &
                  cval, ival, rval, ALIGNMENT=alignment, SEP=' ')
    end if
    !
    ! -- write the data line, if necessary
    if (line_end) then
      call this%write_line()
    end if
    !
    ! -- finalize the table, if necessary
    if (allow_finalization) then
      call this%finalize()
    end if
    !
    ! -- Return
    return
  end subroutine add_integer

  subroutine add_real(this, rval, finalize)
! ******************************************************************************
! add_real -- add real value to the dataline
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    real(DP), intent(in) :: rval
    logical, intent(in), optional :: finalize
    ! -- local
    logical :: allow_finalization
    logical :: line_end
    character(len=LINELENGTH) :: cval
    integer(I4B) :: ival
    integer(I4B) :: j
    integer(I4B) :: width
    integer(I4B) :: alignment
! ------------------------------------------------------------------------------
    !
    ! -- initialize optional variables
    if (present(finalize)) then
      allow_finalization = finalize
    else
      allow_finalization = .TRUE.
    end if
    !
    ! -- write header
    if (this%icount == 0 .and. this%ientry == 0) then
      call this%write_header()
    end if
    !
    ! -- update index for tableterm
    this%ientry = this%ientry + 1
    !
    ! -- check that ientry is within bounds
    call this%add_error()
    !
    ! -- initialize local variables
    j = this%ientry
    width = this%tableterm(j)%get_width()
    alignment = this%tableterm(j)%get_alignment()
    line_end = .FALSE.
    !
    ! -- add data to line
    if (j == this%ntableterm) then
      line_end = .TRUE.
      call UWWORD(this%dataline, this%iloc, width, TABREAL,                      &
                  cval, ival, rval, ALIGNMENT=alignment)
    else
      line_end = .FALSE.
      call UWWORD(this%dataline, this%iloc, width, TABREAL,                      &
                  cval, ival, rval, ALIGNMENT=alignment, SEP=' ')
    end if
    !
    ! -- write the data line, if necessary
    if (line_end) then
      call this%write_line()
    end if
    !
    ! -- finalize the table, if necessary
    if (allow_finalization) then
      call this%finalize()
    end if
    !
    ! -- Return
    return
  end subroutine add_real
  
  subroutine add_string(this, cval, finalize)
! ******************************************************************************
! add_string -- add string value to the dataline
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    character(len=*) :: cval
    logical, intent(in), optional :: finalize
    ! -- local
    logical :: allow_finalization
    logical :: line_end
    integer(I4B) :: j
    integer(I4B) :: ival
    real(DP) :: rval
    integer(I4B) :: width
    integer(I4B) :: alignment
! ------------------------------------------------------------------------------
    !
    ! -- initialize optional variables
    if (present(finalize)) then
      allow_finalization = finalize
    else
      allow_finalization = .TRUE.
    end if
    !
    ! -- write header
    if (this%icount == 0 .and. this%ientry == 0) then
      call this%write_header()
    end if
    !
    ! -- update index for tableterm
    this%ientry = this%ientry + 1
    !
    ! -- check that ientry is within bounds
    call this%add_error()
    !
    ! -- initialize local variables
    j = this%ientry
    width = this%tableterm(j)%get_width()
    alignment = this%tableterm(j)%get_alignment()
    line_end = .FALSE.
    !
    ! -- add data to line
    if (j == this%ntableterm) then
      line_end = .TRUE.
      call UWWORD(this%dataline, this%iloc, width, TABUCSTRING,                  &
                  cval, ival, rval, ALIGNMENT=alignment)
    else
      call UWWORD(this%dataline, this%iloc, width, TABUCSTRING,                  &
                  cval, ival, rval, ALIGNMENT=alignment, SEP=' ')
    end if
    !
    ! -- write the data line, if necessary
    if (line_end) then
      call this%write_line()
    end if
    !
    ! -- finalize the table, if necessary
    if (allow_finalization) then
      call this%finalize()
    end if
    !
    ! -- Return
    return
  end subroutine add_string
  
  subroutine set_maxbound(this, maxbound)
! ******************************************************************************
! set_maxbound -- reset maxbound
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    integer(I4B), intent(in) :: maxbound
    ! -- local
! ------------------------------------------------------------------------------
    !
    ! -- set maxbound
    this%maxbound = maxbound
    !
    ! -- reset counters
    call this%reset()
    !
    ! -- return
    return
  end subroutine set_maxbound   
  
  subroutine set_title(this, title)
! ******************************************************************************
! set_maxbound -- reset maxbound
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    character(len=*), intent(in) :: title
    ! -- local
! ------------------------------------------------------------------------------
    !
    ! -- set maxbound
    this%title = title
    !
    ! -- return
    return
  end subroutine set_title
  
  subroutine print_list_entry(this, i, nodestr, q, bname)
! ******************************************************************************
! print_list_entry -- write flow term table values
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    integer(I4B), intent(in) :: i
    character(len=*), intent(in) :: nodestr
    real(DP), intent(in) :: q
    character(len=*), intent(in) :: bname
    ! -- local
! ------------------------------------------------------------------------------
    !
    ! -- fill table terms
    call this%add_term(i)
    call this%add_term(nodestr)
    call this%add_term(q)
    if (this%ntableterm > 3) then
      call this%add_term(bname)
    end if
    !
    ! -- return
    return
  end subroutine print_list_entry  
  
  subroutine reset(this)
! ******************************************************************************
! reset -- Private method to reset table counters
! ******************************************************************************
!
!    SPECIFICATIONS:
! ------------------------------------------------------------------------------
    ! -- modules
    ! -- dummy
    class(TableType) :: this
    ! -- local
! ------------------------------------------------------------------------------
    !
    ! -- reset counters
    this%ientry = 0
    this%icount = 0
    this%first_entry = .TRUE.
    !
    ! -- return
    return
  end subroutine reset 

end module TableModule
