%  This script provides an example for reading in experimental data
%  files associated with a series of cocktail recordings began in May
%  2008, in the Center for Visualization and Virtual Environments
%  at the University of Kentucky.
%  Exeriments were recorded with spatially distributed microphones
%  where the speaker of interest (SOI) was recorded separately from
%  the party (multiple simultaneous conversations). The microphone
%  geometry and settings were the same of both recordings, so they can
%  be superimposed at specified power ratios and/or processed separately
%  for performance metric estimations, such as SNR and intelligibility.
%  This script opens the data and parameter files and in a hoping window
%  fashion performs a delay and sum beaformer on the SOI in party noise.
%  Weights applied to each microphone channel base on thier distance from
%  the source.
%    Parameters for adjustment:
%  WP => The balance between close and distance mics can be adjusted base
%        on parameter WP described in the script.
%  SNRDB_DESIRED => The SNR between the SOI and party noise can be set
%                   with parameter SNRDB_DESIRED.
%  HPF => A high-pass filter is applied to remove components with longer
%         wavelengths resulting from room modes with parameter HPF which
%         is the high-pass cutoff in Hz.
%  WS =>  The processing window size WS can be changed, but has no impact
%         signal quality performance.
%    Script Outputs:
%  The script creates a plot of source and microphone positions
%  so the geometry can be observed, it then plays and plots the
%  solo SOI using the closest mic, the SOI plus party noise using
%  the closest mic, and finally the beamformed SOI.  Computed SNR 
%  closest mics before and after beamforming are computed. Plots
%  of the intelligibility indecies are generated for the SOI every
%  100ms before and after beamforming, as well as the average
%  intelligibity index and it standard deviation over the recording.
%
%  This script requires dsb.m, arweights.m, intel.m and sii.m
%  from the array toolbox.
%     Written by Kevin D. Donohue (donohue@engr.uky.edu) and 
%     ArulKumaran Muthukumarasamy (arulkumaran@uky.edu) Sept. 2008
%

clc
clear all
%SOI index to select speakers 1 through 3
soi = 3;
dpath = 'cocktail_080108_cluster/';  %  Directory containing recording parameters and data
% dpath='F:\cocktail and tc and pesq\ArrayToolbox';
% Processing paraemters
% wp => mic weight distibtion where 0 results in equal weights,
% and 1 results in an inverse distance weighting where they are
% scaled such that the closest mic gets a weight of 1. A positive
% number gives more weight to closer mics, and a negative number
% gives more weight to distant mics:

wp = 1;
% Set SNR in dB for conversation of interest relative to 
%  cocktail party noise (average power ratio over all mics)
snrdb_desired = -7;
% Processing window size in seconds for reading in data and applying 
% the current source position number assoicated with the correspond
% time the window includes.
ws = 40e-3;
% High-pass cutoff in Hertz for filtering signal before beamforming
fc = 300;


% Name of multichannel wavefile with source recordings
sfile = [dpath, 'soi' int2str(soi) '.wav']; 
% Name of multichannel wavefile with cocktail party/noise recordings
nfile = [dpath, 'party' int2str(soi) '.wav'];
% Name of file with source positions listed over time
sposfile = [dpath, 'soi' int2str(soi) 'pos.txt']; 
% Name of file with static microphone position
mposfile = [dpath, 'mpos.txt'];
% Name of file with measured environment parameters (i.e. speed of sound) 
parmfile = [dpath, 'info.txt'];

% Load files associated with recordings
spos = load(sposfile,'-ascii');  %  Source Positions

mpos = load(mposfile,'-ascii'); % Mic Postions
%mpos = mpos/100;  %  Convert mic positions to meters
%  Get speed of sound out of info file
fid = fopen(parmfile);            
h = textscan(fid,'%s');
for k=2:length(h{1})
    if ~isempty(strmatch(h{1}(k),'=')) && ~isempty(strmatch(h{1}(k-1),'c'))
        c = str2double(h{1}(k+1));
    end
end
fclose(fid);  %  Close info file
%  Plot Mic and Speaker geometry
figure
plot3(mpos(1,:),mpos(2,:),mpos(3,:),'ob')
axis([0 4 0 4 0 2.5]);  % Set axis on the order of recording space
grid
hold on %  Superimpose speaker positions
plot3(spos(:,2),spos(:,3),spos(:,4),'xr')
xlabel('Meters X')
ylabel('Meters Y')
zlabel('Meters Z')
title('Mic Positions (Blue o), Source Positions (red x)')
hold off
pause(.2)

%  Reads in full files get file information and compute
%  average power in signals and noise
[y, fs] = wavread(nfile);  %  party noise
[siglen1,chans] = size(y);  % Noise signal length and channels
nospower = mean(std(y).^2);  %  Power in each channel
[y, fs] = wavread(sfile);   %  Speaker recording
[siglen2, chans] = size(y);   % Speaker signal length and channels
siglen = min([siglen1, siglen2]);  % Find the shorter signal length
% Compute linear scaling factor to achieve SNR 
sigpower = mean(std(y).^2);  % power in each channel;
%  Additional SNR in dB to match required
dBgain = snrdb_desired - 10*log10(sigpower/(nospower+eps));
swt = 10^(dBgain/20);  % Linear scale factor
% Compute High-pass filter coefficients
[b,a] = butter(4,fc/(fs/2),'high');

%  Initalize sample indecies to step through recordings one
%  window at a time
segstart = 1;  % Signal time index for beginning of first window
segend = segstart+round(ws*fs);  % Signal time index for end of first window
wsc = ws; % Initalize current time window end point in seconds 
loopcount = 0;  %  Initalize loop counter for array indexing
y = [];  %  Initalize ouput arrays for beamforming
%  Initalize other arrays for comparison and assesment
%  purposes:
%  closest mic signal, solo signal beamformed, and cocktail
%  noise (no signal) beamformed 
totclosemic = []; sig_beam=[]; nos_beam=[];  
%  Initalize arrays for closest mic signals
sigclosemic = []; nosclosemic=[];
%  Beamform the data in loop until current segment end sample
%  is less than total signal length 
while segend <= siglen
    % Read in short segment of data form
    x= wavread(nfile,[segstart segend]);  % cocktail party
    xn = x; % cocktail party noise signal
    xi = wavread(sfile,[segstart segend]); % Speaker of interest (SOI)
    xi = swt*xi; % scaled SOI at specfied SNR
    x = x+ xi;  %  Combine SOI with party noise at specified average SNR
    
    %  If first time in loop initalize previous window data
    %  with zeros, otherwise update with actual data from previous window
    if loopcount > 0;  % Update
       % Filter using final condition from last run as initial conditions
       [x,xf1] = filter(b,a,x,xf1);  
       [x_nos,xf1_nos] = filter(b,a,xn,xf1_nos);
       [x_sig,xf1_sig] = filter(b,a,xi,xf1_sig);
       % update previous window data
       xPrev = xp;
       xPrev_nos = xp_n;
       xPrev_sig = xp_s;

    else  %  Initalize
       % Filter using zeros as initial conditions
       [x,xf1] = filter(b,a,x);
       [x_sig,xf1_sig] = filter(b,a,xi);
       [x_nos,xf1_nos] = filter(b,a,xn);
       xPrev = zeros(size(x));
       xPrev_sig = zeros(size(xi));
       xPrev_nos = zeros(size(xn));
       slocpre = [nan, nan, nan];
    end
    %  Determine distances of SOI location to microphone for weighting.
    [dum indx] = min(abs(spos(:,1)-(wsc-ws/2))); %  Find location corresponding
    sloc = spos(indx(1),2:4);                    %   to current time window
    %  If source is active use, current location from info file 
    if ~isnan(sloc(1))
        d = (sloc'*ones(1,chans)-mpos);
        slocpre = sloc;
        spflag = 0;  % clear "skip-processing" flag
    elseif ~isnan(slocpre(1));   %  If not active, use previous location
        sloc = slocpre;
        d = (sloc'*ones(1,chans)-mpos);
        spflag = 0; % clear skip processing flag
    else  % If previous location not active (i.e. first frame)
        %  update with zero and skip processing
        xp = zeros(length(x),chans); 
        xp_n = zeros(length(xn),chans);
        xp_s = zeros(length(xi),chans);
        y = [y; zeros(length(x),1)];  % pad with zeros
        totclosemic = [totclosemic; zeros(length(x),1)];
        sigclosemic = [sigclosemic; zeros(length(xi),1)];
        nosclosemic = [nosclosemic; zeros(length(xn),1)];
        nos_beam = [nos_beam; zeros(length(xn),1)];
        sig_beam = [sig_beam; zeros(length(xi),1)];
        spflag = 1;  % Set skip processing flag 
    end
    %  If valid location is present, beamform on that location
    if spflag == 0
        %  compute mic channel weights based on inverse distance
        ar = arweights(sqrt(sum(d.^2)));
        %  Normalize weight value of channel closest to SOI
        [nscl, lmax] = max(ar);
        % Raise weights to power to emphasize/deemphasize distant mics
        arw = (ar/nscl(1)).^wp; 
        % expand out weight in a matrix to multiple with signal
        ww = ones(length(x),1)*arw;
        xp = x.*ww;  % Apply weights to SOI  plus party noise
        xp_n = xn.*ww;  % Apply weights to party noise only
        xp_s = xi.*ww;  % Apply weight to solo SOI
        %  Apply delay and sum beamformer 
        ytemp = dsb(xp, xPrev, fs, sloc', mpos, c); % Combined
        ytemp1 = dsb(xp_n, xPrev_nos, fs, sloc', mpos, c); % noise only
        ytemp2 = dsb(xp_s, xPrev_sig, fs, sloc', mpos, c); % solo SOI 
        %  Beamformed signals 
        y = [y; ytemp/sum(arw)];  %  Concatenate with previous combined
        nos_beam =[nos_beam;ytemp1/sum(arw)]; %  Concatenate with previous noise only
        sig_beam =[sig_beam;ytemp2/sum(arw)]; %  Concatenate with previous SOI only
        %  Closest mic signals for comparisons with single mic recordings
        totclosemic = [totclosemic; x(:,lmax(1))]; % Concatenate closest mic combined
        sigclosemic = [sigclosemic; xi(:,lmax(1))]; % Concatenate closest mic SOI only
        nosclosemic = [nosclosemic; xn(:,lmax(1))]; % Concatenate closest mic noise only 
      
    end
    %  Update for next window of data
    slocpre= sloc;  %  Update Previous Location
    wsc = wsc + ws; %  Update time window end point in seconds
    segstart = segend + 1;  % Update segement beginging
    segend = round(wsc*fs); %  Update segment end
    loopcount = loopcount + 1;
end

    %  Filter close mic signals just as beamformed was for fair comparison
    sigclosemic = filter(b,a,sigclosemic);
    nosclosemic = filter(b,a,nosclosemic);
    
    %  create time axes for plotting
    tsig = [0:length(sigclosemic)-1]/fs;
    tbf = [0:length(y)-1]/fs;
    tcm = [0:length(totclosemic)-1]/fs;
    
    % Plot close mic signal in green with party noise signal in red
    figure
    plot(tsig,sigclosemic,'g')
    xlabel('Seconds')
    title('SOI Signal (green)')
    hold on
    
    % Play close mic signal without party noise
    soundsc(sigclosemic,fs)
    pause(tsig(end)+1)
    plot(tcm,totclosemic,'r')
    xlabel('Seconds')
    title('SOI Signal (green), Closest Mic in noise Signal (red)')

    %  Play combined SOI and party noise for close mic signal
    soundsc(totclosemic,fs)
    pause(tcm(end)+1)
    plot(tbf,y,'b')
    xlabel('Seconds')
    title('SOI Signal (green), Closest Mic Signal (red), Beamformed Signal (blue)')
    % Play beamformed signal 
    soundsc(y,fs)
    hold off
    
    % Estimate the SNR value of the closest mic
    rmssig = mean(std(sigclosemic).^2);
    rmsnos = mean(std(nosclosemic).^2);
    snr_out = 10*log10(rmssig/(rmsnos+eps));
    disp(['1. SNR of closest mic is ' num2str(snr_out) 'dB']);
    
    % Estimate the SNR value of the beamformed signals
    rmssigb = mean(std(sig_beam).^2);
    rmsnosb = mean(std(nos_beam).^2);
    snrb_out = 10*log10(rmssigb/(rmsnosb+eps));
    disp(['2. SNR of beamformed signal is ' num2str(snrb_out) 'dB']);
    
    iwin = 100e-3;  % Window over which to estimate intelligibility
                 
    % Estimate the intelligibility for the closest mic
    [sii_cm,tax] = intel(sigclosemic,nosclosemic,fs,iwin);
    sii_m = mean(sii_cm);
    sii_s = std(sii_cm);
    disp(['3. Mean Intelligibility for closest mic is ' num2str(sii_m) ]);
    disp(['Standard deviation of Intelligibility for closest mic is ' num2str(sii_s) ]);
    
    % Estimate the intelligibility for the Beamformed signals
    [siib,taxb] = intel(sig_beam,nos_beam,fs,iwin);
    siib_m = mean(siib);
    siib_s = std(siib);
    disp(['4. Mean Intelligibility for beamformed signal is ' num2str(siib_m) ]);
    disp(['Standard deviation of Intelligibility for beamformed signal is ' num2str(siib_s) ]);

    % plot the speech intelligibility index of the closest mic and
    % beamformed signals.
    figure;
    plot(tax,sii_cm,'b');
    hold on
    plot(taxb,siib,'r');
    xlabel('time in seconds');
    ylabel('speech intelligibility index');
    title('Intelligibility of closest mic signals (blue) and Beamformed signals (red)');
