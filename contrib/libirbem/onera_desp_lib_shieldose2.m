function [ProtDose,ElecDose,BremDose,SolDose,TotDose] = onera_desp_lib_shieldose2(ProtSpect,ElecSpect,SolSpect,Target,varargin)
% function [ProtDose,ElecDose,BremDose,SolDose,TotDose] = onera_desp_lib_shieldose2(ProtSpect,ElecSpect,SolSpect,Target,...)
% returns dose rate (rads/unit_time) vs depth for average incident spectrum
%   for trapped protons (ProtDose), trapped electrons (ElecDose),
%   Bremsstrahlung (BremDose), solar protons (SolDose),
%   and total dose (TotDose)
% outputs provide dose for 3 geometris
% xxxDose(:,1) - DOSE IN SEMI-INFINITE ALUMINUM MEDIUM
% xxxDose(:,2) - DOSE AT TRANSMISSION SURFACE OF FINITE ALUMINUM SLAB SHIELDS
% xxxDose(:,3) - 1/2 DOSE AT CENTER OF ALUMINUM SPHERES 
% Three spectra are required:
% ProtSpect - Trapped Proton Spectrum
% ElecSpect - Trapped Electron Spectrum
% SolSpect - Solar Proton Spectrum
% The three *Spect arguments have 2 forms:
% Exponential spectrum:
% xxxSpect.Erange = [Emin Emax] energy range in MeV
% xxxSpect.E0 (efolding energy in MeV)
% xxxSpect.N0 (normalization factor #/cm^2/MeV/unit_time)
% xxxSpect.form = 'E' for energy, 'R' for rigidity
%  (i.e. is the spectrum exponential in energy or rigidity)
% Tabular spectrum:
% xxxSpect.E energy in MeV
% xxxSpect.Flux in #/cm^2/MeV/unit_time
% xxxSpect.Erange = [Emin Emax] energy range in MeV (optional)
%  (an empty spectrum will be treated as a zero flux)
% ***SolSpect is expected as a flux, not a mission fluence***
% Target.depth = depth of shielding
% Tartget.unit = units for depth ('mils'=1,'g/cm2'=2, or 'mm'=3)
% Target.material =
%              Al, 1 = AL DETECTOR
%                C,graphite, 2 =GRAPHITE DETECTOR
%                Si, 3 = SI DETECTOR
%                air, 4 = AIR DETECTOR
%                bone, 5 = BONE DETECTOR
%                CaFl, 6 = CALCIUM FLUORIDE DETECTOR
%                GaAr, 7 = GALLIUM ARSENIDE DETECTOR
%                LiFl, 8 = LITHIUM FLUORIDE DETECTOR
%                SiO2, 9 = SILICON DIOXIDE DETECTOR
%               Tissue, 10 = TISSUE DETECTOR
%               water, H2O, 11 = WATER DETECTOR
% options:
% shieldose(...,'INUC',n)
%         INUC = 1, NO NUCLEAR ATTENUATION FOR PROTONS IN AL
%                2, NUCLEAR ATTENUATION, LOCAL CHARGED-SECONDARY ENERGY
%                      DEPOSITION
%                3, NUCLEAR ATTENUATION, LOCAL CHARGED-SECONDARY ENERGY
%                      DEPOSITION, AND APPROX EXPONENTIAL DISTRIBUTION OF
%                      NEUTRON DOSE (default)
% shieldose(...,'NPTS',n)
%   set number of points on energy integrals
%   default is n = larger of 20 or length of flux table
% shieldose(...,'file_path',file_path)
%   specify path to find shared libraray and .dat files
%   if not in Matlab path
% shieldose(...,'perYear',1)
%   1 = specify that input is in flux per second,
%     but output should be in rads per year

INUC = 3;
NPTS = 20;
perYear = 0;
EUNIT = 1; % dummy--energy must be in MeV
DURATN = 1; % dummy--shieldose treats flares as fluence & duration but we're not doing that

for i = 1:2:length(varargin),
    var = varargin{i};
    if ~ischar(var),
        error('Non-string provided as option keyword to "%s"',mfilename);
    end
    val = varargin{i+1};
    switch(lower(var)),
        case {'inuc'},
            INUC = val;
        case {'npts'},
            NPTS = val;
        case {'peryear'},
            perYear = val;
        otherwise
            error('Unknown option "%s" in "%s"',var,mfilename);
    end
end

IDET = shieldose2_idet(Target.material);
IUNIT = shieldose2_iunit(Target.unit);
IMAX = length(Target.depth);

[EMINS,EMAXS,ESin,SFLUXin,JSMAX] = shieldose2_spect(SolSpect);
[EMINP,EMAXP,EPin,PFLUXin,JPMAX] = shieldose2_spect(ProtSpect);
[EMINE,EMAXE,EEin,EFLUXin,JEMAX] = shieldose2_spect(ElecSpect);
NPTSP = max([JPMAX,JSMAX,NPTS]);
NPTSE = max([JEMAX,NPTS]);

onera_desp_lib_load;

IMAXI = 71;
ProtDose = repmat(nan,IMAXI,3);
ElecDose = ProtDose;
BremDose = ProtDose;
SolDose = ProtDose;
TotDose = ProtDose;
ProtDosePtr = libpointer('doublePtr',ProtDose);
ElecDosePtr = libpointer('doublePtr',ElecDose);
BremDosePtr = libpointer('doublePtr',BremDose);
SolDosePtr = libpointer('doublePtr',SolDose);
TotDosePtr = libpointer('doublePtr',TotDose);

calllib('onera_desp_lib','shieldose2_',IDET,INUC,IMAX,IUNIT,Target.depth,...
    EMINS,EMAXS,EMINP,EMAXP,NPTSP,EMINE,EMAXE,NPTSE,...
    JSMAX,JPMAX,JEMAX,EUNIT,DURATN,...
    ESin,SFLUXin,EPin,PFLUXin,EEin,EFLUXin,...
    SolDosePtr,ProtDosePtr,ElecDosePtr,BremDosePtr,TotDosePtr);

SolDose = get(SolDosePtr,'value');
ProtDose = get(ProtDosePtr,'value');
ElecDose = get(ElecDosePtr,'value');
BremDose = get(BremDosePtr,'value');
TotDose = get(TotDosePtr,'value');

SolDose = SolDose(1:IMAX,:);
ProtDose = ProtDose(1:IMAX,:);
ElecDose = ElecDose(1:IMAX,:);
BremDose = BremDose(1:IMAX,:);
TotDose = TotDose(1:IMAX,:);

if perYear,
    yearseconds = 365*24*60*60;
    SolDose = SolDose*yearseconds;
    ProtDose = ProtDose*yearseconds;
    ElecDose = ElecDose*yearseconds;
    BremDose = BremDose*yearseconds;
    TotDose = TotDose*yearseconds;
end

function IDET = shieldose2_idet(IDET)

if ~isnumeric(IDET),
    switch(lower(IDET)),
        case {'al'}, IDET = 1;
        case {'c','graph','graphite'}, IDET = 2;
        case {'si'}, IDET = 3;
        case {'air'}, IDET = 4;
        case {'bone'}, IDET = 5;
        case {'cafl'}, IDET = 6;
        case {'gaar'}, IDET = 7;
        case {'lifl'}, IDET = 8;
        case {'sio2'}, IDET = 9;
        case {'tissue'}, IDET = 10;
        case {'water','h2o'}, IDET = 11;
        otherwise
            error('Unknown IDET "%s" in "%s"',IDET,mfilename);
    end
end

function IUNIT = shieldose2_iunit(IUNIT)

if ~isnumeric(IUNIT),
    switch(lower(IUNIT)),
        case {'mils'}, IUNIT = 1;
        case {'g/cm^2','g/cm2'}, IUNIT = 2;
        case {'mm'}, IUNIT = 3;
        otherwise
            error('Unknown IUNIT "%s" in "%s"',IUNIT,mfilename);
    end
end

function [EMIN,EMAX,Ein,FLUXin,NPTS] = shieldose2_spect(Spect)
if isempty(Spect),
    EMIN = 0.1;
    EMAX = 1e4;
    Ein = 0;
    FLUXin = 0;
    NPTS = 0;
elseif isfield(Spect,'E0'),
    EMIN = Spect.Erange(1);
    EMAX = Spect.Erange(end);
    Ein = [0 0 0];
    FLUXin = [Spect.E0 Spect.N0 0];
    if lower(Spect.form(1))=='r',
        FLUXin(3) = 1; % exponential in rigidity
    end
    NPTS = 3;
else
    Ein = Spect.E;
    FLUXin = Spect.Flux;
    while ~isempty(FLUXin) && (FLUXin(end)<=0),
        FLUXin = FLUXin(1:(end-1));
        Ein = Ein(1:(end-1));
    end
    if isempty(FLUXin) || all(FLUXin==0), % all zeros or negative!
        [EMIN,EMAX,Ein,FLUXin,NPTS] = shieldose2_spect([]);
        return;
    end
    % otherwise, replace zeros in the middle of the spectrum with something
    % divided by 10 (don't make them too small or shieldose2's splines
    % might screw up.
    FLUXin(FLUXin==0) = min(FLUXin(FLUXin>0))/10;
    NPTS = length(Ein);
    if isfield(Spect,'Erange'),
        EMIN = Spect.Erange(1);
        EMAX = Spect.Erange(end);
    else
        EMIN = Ein(1);
        EMAX = Ein(end);
    end
end
