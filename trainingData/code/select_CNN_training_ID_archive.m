classdef select_CNN_training_ID_archive < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        SaveandContinueButton       matlab.ui.control.Button
        RemoveFrontButton           matlab.ui.control.Button
        ProcessAllFramesButton      matlab.ui.control.Button
        SelectFrontButton           matlab.ui.control.Button
        FramestoPlotEditField       matlab.ui.control.NumericEditField
        FramestoPlotEditFieldLabel  matlab.ui.control.Label
        LoadVideoButton             matlab.ui.control.Button
        StartFrameEditField         matlab.ui.control.NumericEditField
        StartFrameEditFieldLabel    matlab.ui.control.Label
        SelectCurrentFilename       matlab.ui.control.DropDown
        SelectFileLabel             matlab.ui.control.Label
        SelectCurrentDirectory      matlab.ui.control.DropDown
        SelectDirectoryLabel        matlab.ui.control.Label
        TextArea                    matlab.ui.control.TextArea
        TextAreaLabel               matlab.ui.control.Label
        SelectFiles                 matlab.ui.control.Button
        UIAxes                      matlab.ui.control.UIAxes
        CameraIDEditField            matlab.ui.control.EditField
        CameraIDEditFieldLabel       matlab.ui.control.Label
        ArchiveDirectoryEditField    matlab.ui.control.EditField
        ArchiveDirectoryEditFieldLabel matlab.ui.control.Label
        BrowseArchiveButton          matlab.ui.control.Button
    end

    
    properties (Access = private)
        path % path to video files
        rootDir % location of "waveIMG" on filesystem
        info % structure w/ video info 
        icp  % structure w/ intrinsic cam parameters
        beta0% extrinsic cam params
        vid  % structure w/ current video
        U    % image horizontal coord
        V    % image vertical coord
        X    % grid cross-shore coord
        Y    % grid alongshore coord
        Uint % (x,y) U-coord in image
        Vint % (x,y) V-coord in image
        videoFrameIndices % frame indices corresponding to desired sample rate
        numberVideoFrames % number of frames at desired sample rate
        IMG  % current rectified image frame
        imageOutputDirecotry % this is where the training images go
        imageOutputFilename  % the name of the current training image
        labelOutputDirectory % this is where the training labels go
        labelOutputFilename  % same as imageOutput...   
        logFile
        log
        logNum % the current frame number
        currentFrameIndex 
        videoFile
        LBL
        cwd
        archiveRoot
    end
    
methods (Access = private)
        function uigetdirs(app)
            % Pick multiple files or directories using Java widgets                                                                                                                                                                                                                
            % by Andrew Janke 2011                                                                                                                                                                                                                                                 
            import javax.swing.JFileChooser;

            if (nargin == 0) | isempty(app.path) % Allow a null argument.                                                                                                                                                                                      
                app.path{1} = pwd;
            end
            
            jchooser = javaObjectEDT('javax.swing.JFileChooser', app.path{1});

            jchooser.setFileSelectionMode(JFileChooser.FILES_AND_DIRECTORIES);
            if nargin > 1
                jchooser.setDialogTitle(dialog);
            end

            jchooser.setMultiSelectionEnabled(true);

            status = jchooser.showOpenDialog([]);

            if status == JFileChooser.APPROVE_OPTION
                jFile = jchooser.getSelectedFiles();
                app.path{size(jFile, 1)}=[];
                for i=1:size(jFile, 1)
                	app.path{i} = char(jFile(i).getAbsolutePath);
                end

            elseif status == JFileChooser.CANCEL_OPTION
               disp('No directories selected.')
            else
               error('Error occured while picking file.');
            end 
        app.path = app.path';   
        end
        
        function addDirs(app)
            % add these to the directory selector
            app.path
            for jj = 1:length(app.path)
                FolderNames = regexp(app.path{jj},filesep,'split');
                DirectoryItems{jj} = [char(FolderNames{end-1}), filesep,char(FolderNames{end})];
            end
            app.SelectCurrentDirectory.Items     = DirectoryItems;
            app.SelectCurrentDirectory.ItemsData = app.path;
            app.SelectCurrentDirectory.Value     = app.path{1};
            %
            % add the filenames to the list
            addFiles(app);
        end
        
        function addFiles(app)
            filesAVI = dir([app.SelectCurrentDirectory.Value, filesep,'*.avi']);
            filesMP4 = dir([app.SelectCurrentDirectory.Value, filesep,'*.mp4']);
            fileNames = [filesAVI; filesMP4];
            for jj = 1:length(fileNames)
                fileName = fileNames(jj).name;
                FileItems{jj} = fileName;
            end
            app.SelectCurrentFilename.Items     = FileItems;
            app.SelectCurrentFilename.ItemsData = FileItems;
            app.SelectCurrentFilename.Value     = FileItems{1};
        end
        
        function load_video(app)                                                                                                                                                                                    
            % USAGE: app = load_video(app)
            %
            % function reads video, grid, and camera parameters;
            % loads the current video, but does not rectify.
            ID = strtrim(app.CameraIDEditField.Value);
            if isempty(ID)
                uialert(app.UIFigure, 'Enter the camera ID used by define_camera_parameters_new.m (for example top21, bot21, top18, bot18, or rod13).', 'Camera ID required');
                error('select_CNN_training_updated2:MissingCameraID','Camera ID is required.');
            end
            try
                [info, icp, beta0, descriptionStr] = define_camera_parameters_new(ID);
                app.info.description = descriptionStr;
            catch ME
                uialert(app.UIFigure, ME.message, 'Camera ID error');
                rethrow(ME);
            end
            %
            app.info = info;
            app.icp  = icp;
            app.beta0= beta0;
            %
            videoDir = [app.SelectCurrentDirectory.Value, filesep];
            videoFile = app.SelectCurrentFilename.Value;
            timeFile = [videoDir, filesep, videoFile(1:end-4),'.xml']; %find all videos in source folder
            fprintf('\n loading video %s \n',app.SelectCurrentFilename.Value)
            %
            % load video
            app.videoFile = [videoDir,filesep,videoFile];
            app.vid   = VideoReader([videoDir,filesep,videoFile]);
            vidHz = app.vid.FrameRate;
            vidDr = app.vid.Duration;
%

            samp  = round(vidHz/app.info.freq);
            app.videoFrameIndices = 1:samp:app.vid.NumFrames;
            app.numberVideoFrames = length(app.videoFrameIndices);
            %
            app.StartFrameEditField.Value = min(app.StartFrameEditField.Value,app.numberVideoFrames-3);
            try app.FramestoPlotEditField.Limits(2) = min(app.FramestoPlotEditField.Value,app.numberVideoFrames-app.StartFrameEditField.Value-3);
            catch keyboard
            end
            % prepare image (U,V) coordinates for rectification
            [app.U, app.V] = meshgrid(0:icp.NU-1, 0:icp.NV-1);
            % generate grid (X,Y) coords for transformation
            % [app.X,app.Y] = meshgrid(info.X_min:info.X_res:info.X_max,info.Y_min:info.Y_res:info.Y_max);   %define image grid
            app.X = app.info.X_min:app.info.X_res:app.info.X_max;
            app.Y = app.info.Y_min:app.info.Y_res:app.info.Y_max;
            % may need to correct for tide later
%                 %generate time                                                                                                                                                                                       
% %     fid = fopen(timeFile);                                                                                                                                                                              
% %     l = fgetl(fid);                                                                                                                                                                                      
% %     fclose(fid);                                                                                                                                                                                         
% %     startTimeStr = regexp(l, '(?<=<StartTime>).*(?=</StartTime>)', 'match');                                                                                                                             
% %     keyboard                                                                                                                                                                                             
% %     startTime = datetime(startTimeStr{1}, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z''', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss.SSSS');                                                
% % %}
% %             %load NAVD water level                                                                                                                                                                                   
% %             [tz,z_tide] = load_FRF_waterlevels(startDate,endDate);
%             z_tide    = zeros(size(app.X));
%             % map grid points to image coords
%             [app.Uint,app.Vint]  = getUVfromXYZ(app.X,app.Y, z_tide, icp, beta0);
%             %
%             % get first frame
%             frameNum = app.StartFrameEditField.Value;
%             % load frame
%             IMGraw  = double(rgb2gray(read(app.vid,1)));
%             % interpolate to grid points
%             app.IMG = interp2(app.U, app.V, IMGraw, app.Uint, app.Vint, 'linear', nan);
 
        end
        
        function rectify_video(app)
          % USAGE: app = rectify_video(app)
          %
          % rectify 3 frames beginning with Start Frame, 
          % then advance Start Frame by 1.

          %generate time
          %     fid = fopen(timeFile);
          %     l = fgetl(fid);
          %     fclose(fid);
          %     startTimeStr = regexp(l, '(?<=<StartTime>).*(?=</StartTime>)', 'match');
          %     keyboard
          %     startTime = datetime(startTimeStr{1}, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z''', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss.SSSS');
          % %}
          %             %load NAVD water level
          %             [tz,z_tide] = load_FRF_waterlevels(startDate,endDate);
          % map grid points to image coords
            [xx,yy] = meshgrid(app.X,app.Y);  
            z_tide    = zeros(size(xx));
            [app.Uint,app.Vint]  = getUVfromXYZ(xx,yy, z_tide, app.icp, app.beta0);
            %
            % get first frame
            frameNum = app.StartFrameEditField.Value;
            frames   = app.videoFrameIndices(frameNum:frameNum+2);
            for ii   = 1:3
                % load frame    
                IMGraw  = double(rgb2gray(read(app.vid,frames(ii))));
                % interpolate to grid points
                IMG(:,:,ii) = interp2(app.U, app.V, IMGraw, app.Uint, app.Vint, 'linear', nan);
            end
            app.IMG = uint8(IMG);
            app.StartFrameEditField.Value = min(frameNum+1,app.numberVideoFrames);
        end
        
        function rectify_and_display(app)
            % need a stop index for this loop similar to
            % StartFrameEditField
            numFrames = app.FramestoPlotEditField.Value;
            for jj = app.StartFrameEditField.Value + [0:numFrames-1]
                % rectify current frame
                rectify_video(app)
                % now plot the current image
                cla(app.UIAxes)
                imagesc(app.UIAxes, app.X, app.Y, app.IMG)
               
                colormap(app.UIAxes,'bone')
                axis(app.UIAxes,'equal')
                set(app.UIAxes,'tickdir','out','ticklabelinterpreter','latex','fontsize',15)
                close(gcf)
                %got primitive text error
                %app.UIAxes.Title = sprintf("Psuedo-Image: # %d",jj);
                set(app.UIAxes.Title,'String',sprintf("Psuedo-Image: # %d",jj));
                %set(app.UIAxes,'plotboxaspectratio',get(app.UIAxes,'DataAspectRatio'))
                pause(0.05)
                app.currentFrameIndex = app.videoFrameIndices(jj);
            end
            app.LBL = uint8(zeros(app.info.Ny,app.info.Nx));
        end
        
        function select_front(app)
            %get roi: roi = drawfreehand(app.UIAxes);
            roi = drawfreehand(app.UIAxes, "Closed", 0, "Smoothing", 0); %closed =1 open = 0
            if size(roi.Position,1)<4, return, end
            hold(app.UIAxes, 'on');
            plot(app.UIAxes,roi.Position(:,1),roi.Position(:,2),'.b','MarkerSize', 5);
            roi.Visible = 'off';
            %keyboard
            %[xx,yy] = meshgrid(app.X,app.Y);
            %extract x,y : inPoly  = inpolygon(xx,yy,roi.Position(:,1),roi.Position(:,2));
            %inPoly  = inpolygon(xx,yy,roi.Position(:,1),roi.Position(:,2));
            %[row,column] = find(inPoly);
            %inds = sub2ind(size(xx),row,column);
            %inds = find(inPoly);
            %hold(app.UIAxes,'on')
            %plot(app.UIAxes,xx(inds),yy(inds),'.b','markersize',5)
            
            

            x = roi.Position(:,1);
            y = roi.Position(:,2);
            
            t = [0; cumsum(sqrt(diff(x).^2 + diff(y).^2))]; % cum distance for splin interp
            [tu, I_keep, I_drop] = unique(t);
            xu = x(I_keep);
            yu = y(I_keep);
            min_res = min(app.info.X_res , app.info.Y_res)/sqrt(2); % this res can be used to set how many points we want in the line

            total_length = t(end);
            num_points = ceil(total_length / min_res);

            tt = linspace(0, t(end), num_points); % can use num points instad of 1000 but I get some issues during one or two runs 
            

            
            z = xu+sqrt(-1)*yu;

            zz = makima(tu, z, tt);% roi_coords

            xx = real(zz);
            yy = imag(zz);
                        

            plot(app.UIAxes, xx, yy, '.r', 'markersize', 8);
            hold(app.UIAxes, 'off');
            
            roi_coords = [xx(:), yy(:)];
            
            delta_x = (xx - app.info.X_min)/app.info.X_res;
            delta_y = (yy - app.info.Y_min)/app.info.Y_res;
            
            roi_pixels = [delta_x(:)+1, delta_y(:)+1];
            
            
            
            %add coords and add pixels to logfile 
            
            if length(app.log) >= app.logNum
                disp('app.log = app.logNum')
                num_fronts = length(app.log(app.logNum).roi_coords)
    
                
            else
                num_fronts = 0
            end
            
                app.log(app.logNum).roi_coords(num_fronts+1) = {roi_coords};
                app.log(app.logNum).roi_pixels(num_fronts+1) = {roi_pixels};
    
                % old stuff
                app.log(app.logNum).videoFile = app.videoFile;
                app.log(app.logNum).frameIndex = app.currentFrameIndex;

        end
        
        function remove_front(app) % use in poly to cheack if fronts have points that are in essarer, then del points

            
            roi = drawfreehand(app.UIAxes);

            roi_pos = roi.Position;
            
            numFronts = length(app.log(app.logNum).roi_coords);

            hold(app.UIAxes, 'off');
            imagesc(app.UIAxes, app.X, app.Y, app.IMG), %close(gcf)
            hold(app.UIAxes, 'on');


            for ii = 1:numFronts
                 front_coords = app.log(app.logNum).roi_coords{ii};
                 inPoly = inpolygon(front_coords(:,1), front_coords(:,2), roi_pos(:,1), roi_pos(:,2));
                 app.log(app.logNum).roi_coords{ii}(inPoly, :) = [];
                 app.log(app.logNum).roi_pixels{ii}(inPoly, :) = [];
                 plot(app.UIAxes,app.log(app.logNum).roi_coords{ii}(:,1),app.log(app.logNum).roi_coords{ii}(:,2),'.r','MarkerSize', 8);

  
            end
            

            end
            % Set up figure handle visibility, run ginput, and return state
            %fhv = app.UIFigure.HandleVisibility;        % Current status
            %app.UIFigure.HandleVisibility = 'callback'; % Temp change (or, 'on') 
            %set(0, 'CurrentFigure', app.UIFigure)       % Make fig current  
            %roi       = ginput(1);
            %app.UIFigure.HandleVisibility = fhv;
            %
            % convert from (x,y) to nearest image index
            %[xx,yy]   = meshgrid(app.X,app.Y);
            %~,index] = min(abs((roi(1)-xx(:))).^2 + (roi(2)-yy(:)).^2)
            %
            % loop over fronts to find which contains roi
            %numFronts = length(app.log(app.logNum).indices);
            %imagesc(app.UIAxes, app.X, app.Y, app.IMG), close(gcf)
            %hold on,
            
            %for jj = 1:numFronts
             %   indFront = app.log(app.logNum).indices(jj);
             %   if any(index==indFront{:})
             %       keyboard
             %       app.log(app.logNum).indices{jj} = [];
             %       continue
             %   end
             %   plot(app.UIAxes,xx(indFront{:}),yy(indFront{:}),'.b','markersize',5)            
            %end  
         function save_continue(app) % will save the font data to a file, this will be:
            % roi pixels and roi coords
            log = app.log;
            save(app.logFile,'log')
         end
    

   end

    
    

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.TextArea.Value = { ...
                '1) Select your local waveIMG folder.', ...
                '2) Enter the camera ID used by define_camera_parameters_new.m.', ...
                '3) Select the video directory or files.', ...
                '4) Choose the training archive directory.'};
            drawnow;
            app.UIFigure.WindowState = 'maximized';
            app.UIAxes.Title = [];

            % Select the local waveIMG/code root once at startup.
            app.path = {};
            uigetdirs(app);
            if isempty(app.path)
                app.rootDir = pwd;
            else
                app.rootDir = app.path{1};
            end
            addpath(genpath(app.rootDir));

            % Default archive location is alongside the selected waveIMG root.
            app.archiveRoot = fullfile(app.rootDir, 'trainingData');
            if ~exist(app.archiveRoot, 'dir'); mkdir(app.archiveRoot); end
            app.ArchiveDirectoryEditField.Value = app.archiveRoot;

            % Persistent log lives with the code root, as before.
            logDir = fullfile(app.rootDir, 'mat_data');
            if ~exist(logDir,'dir'); mkdir(logDir); end
            app.logFile = fullfile(logDir, 'WaveImageSpecs.mat');

            if exist(app.logFile, 'file')
                S = load(app.logFile, 'log');
                if isfield(S,'log')
                    app.log = S.log;
                end
            end
            if isempty(app.log)
                app.log = struct('videoFile',{},'frameIndex',{},'roi_coords',{},'roi_pixels',{},'labelName',{},'imageName',{});
                app.logNum = 0;
            else
                app.logNum = length(app.log);
            end

            % Sensible default camera ID; user can replace it.
            if isempty(app.CameraIDEditField.Value)
                app.CameraIDEditField.Value = '';
            end
        end

        % Button pushed function: SelectFiles
        function SelectFilesPushed(app, event)
           
            %raw-data parent directory                                                                                                                                                                                                                                            
            %[stat,rootDir] = system('git rev-parse --show-toplevel');
            %app.path{1}    = rootDir(1:end-1);% drop the \n character  
            %app.path{1}    = pwd;
            uigetdirs(app)
            if isempty(app.path)
                app.TextArea.Value = "no directory selected, try again";
                return
            end

            addDirs(app)
            
        end

        % Value changed function: SelectCurrentFilename
        function SelectCurrentFilenameValueChanged(app, event)
            app.SelectCurrentFilename.Value = event.Value;
%             value = app.SelectCurrentFilename.Value;
            %workingDir = app.SelectCurrentDirectory;
            %workingDir = char(workingDir(1))
            % videoPath = [app.SelectCurrentDirectory.Value, filesep, app.SelectCurrentFilename.Value];
        end

        % Drop down opening function: SelectCurrentFilename
        function SelectCurrentFilenameDropDownOpening(app, event)
            addFiles(app);           
        end

        % Button pushed function: LoadVideoButton
        function LoadVideoButtonPushed(app, event)
              app.TextArea.Value = {char('Make sure to hit the save and continue botton before changing the frame or hitting the loading video button or all selections will be lost.');...
                                    char('1) <click> ''Select Front'' button');char('2) hold down cursor and encircle a breaking wave front in the image'); ...
                                    char('3) repeat (1)-(2) until all fronts are highlighted');char('4) <click> ''Save & Continue'' button.')};
              app.TextArea.FontSize = 15;
              load_video(app);
              rectify_and_display(app);
              app.logNum = app.logNum + 1
        end

        % Button pushed function: SelectFrontButton
        function SelectFrontButtonPushed(app, event)
            select_front(app)
        end

        % Button pushed function: ProcessAllFramesButton
        function ProcessAllFramesButtonPushed(app, event)
            % 1) loop over all logs (1:length(app.log)) for logNum 
            for logNum = 1:length(app.log)
                % 1:length(app.log)
                  % 2) load the correct frame for current app.logNum to make
                % app.IMG
                if isempty(app.log(logNum).videoFile), continue, end
                fileInfo = dir(app.log(logNum).videoFile);
                app.path = {fileInfo.folder};
                if isempty(app.path), continue, end
                addDirs(app)
                app.SelectCurrentDirectory.Value = [fileInfo.folder];
                addFiles(app)
                app.SelectCurrentFilename.Value  = fileInfo.name;
                load_video(app)
             
                samp  = round(app.vid.FrameRate/app.info.freq);
                app.StartFrameEditField.Value = (app.log(logNum).frameIndex+1)/samp;
                app.FramestoPlotEditField.Value = 1;
                rectify_and_display(app);
                % 3) create the background image (isblack)
                % 4) create the gray (water) image, everything that's not black
                isBlack          = all(app.IMG<15,3);
                app.LBL(isBlack) = 0;
                isGray          = ~isBlack;
                app.LBL(isGray) = 127;
                % 5) load fronts (one at a time); find indices within threshold
                % distance of front; make those indices white
                % 6) SAVE IMG, and LBL and log the filenames
                
                % first gerate a background(LBL=0)/foreground(LBL=127) mask
                
                %             redChannel   = app.IMG(:, :, 1);
    %             greenChannel = app.IMG(:, :, 2);
    %             blueChannel  = app.IMG(:, :, 3);
    %             blackRed   = redChannel < 15;
    %             blackGreen = greenChannel < 15;
    %             blackBlue  = blueChannel < 15;
    %             maskBlack = blackRed & blackBlue & blackGreen;
    %             maskedLBL = bsxfun(@times, app.LBL, cast(maskBlack,class(app.LBL)));
    %             isGray       = (redChannel == greenChannel == blueChannel);
                %
                % next, for each roi, make LBL=255
                numFronts = length(app.log(logNum).roi_pixels);
                [c,r] = meshgrid(1:app.info.Nx,1:app.info.Ny);
                for ii = 1:numFronts
                    inds = app.log(logNum).roi_pixels{ii}; % pixel coords
                    % for now only! When we re-run, remove the next line
                    rf=inds(:,2)';
                    cf=inds(:,1)';
                    distance = sqrt( (c(:)-cf).^2 + (r(:)-rf).^2);
                    %isFront  = (distance <= app.PixelThresholdEditField.Value);
                    isFront  = (distance <= 1);
                    isFront  = any(isFront,2);
                    app.LBL(isFront)=255; % where set set line size pixel_coords(ii)+ 
                end
    
                
                %
                % overlay the labels on the image
                % the command to use is labeloverlay()
    
                LBLimage = labeloverlay(app.IMG,categorical(app.LBL));
                %
                % display the image before moving on
                imagesc(app.UIAxes, app.X, app.Y, LBLimage); close(gcf)
                hold(app.UIAxes, 'on');
    
               % plot orginal cords next time or tonight - Polk
    
                    
                %app.UIAxes.Title = 'Label Overlay PsuedoImage';
                set(app.UIAxes.Title,'String', 'Label Overlay PsuedoImage');
                
                for ii = 1:numFronts
                    coords = app.log(logNum).roi_coords{ii};
                    plot(app.UIAxes, coords(:,1), coords(:,2), '.r', 'markersize', 8);
                    hold(app.UIAxes, 'on');
                end
                
    
    
                %
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                % Below is for each frame above is for all frames 
                % 
                % 0.4 sec is
                % middle frame btw
                % 
                % archive both IMG and LBL in appropriate directories
                %
                % Use the video filename and framenumber to name the output
                % image
                videoPath   = app.log(logNum).videoFile;
                splitPath   = split(videoPath, [filesep]);
                % keep record of the training image filename, and save .png 
                archiveImages = fullfile(app.archiveRoot,'trainingImages');
                archiveLabels = fullfile(app.archiveRoot,'trainingLabels');
                archiveMeta   = fullfile(app.archiveRoot,'trainingMeta');
                if ~exist(archiveImages,'dir'); mkdir(archiveImages); end
                if ~exist(archiveLabels,'dir'); mkdir(archiveLabels); end
                if ~exist(archiveMeta,'dir'); mkdir(archiveMeta); end
                imageName = fullfile(archiveImages, [splitPath{end}(1:end-4), '_Frame_', num2str(app.log(logNum).frameIndex), '.png']);
                if exist(imageName,'file')
                    overWrite = inputdlg('duplicate training image found, overwrite (1, default) or create new file (0)?','',1,{'1'});                
                end
                iterNumber = 0;
                iterString = [];
                while exist(imageName,'file') && ~(strcmpi(strtrim(overWrite{1}),'1'))                
                    iterNumber = iterNumber+1;
                    iterString = sprintf('_iter_%u',iterNumber);
                    imageName  = fullfile(archiveImages, [splitPath{end}(1:end-4), '_Frame_', num2str(app.log(logNum).frameIndex), iterString, '.png']);                
                end
                app.log(logNum).imageName = imageName;
                imwrite(app.IMG,imageName);
                % keep record of the training label filename, and save .png 
                labelName = fullfile(archiveLabels, [splitPath{end}(1:end-4), '_Frame_', num2str(app.log(logNum).frameIndex), iterString, '.png']);            
                app.log(logNum).labelName = labelName;
                imwrite(app.LBL,labelName);
                save_continue(app)
                %keyboard
            end

        end

        % Button pushed function: RemoveFrontButton
        function RemoveFrontButtonPushed(app, event)
            remove_front(app)
        end

        % Button pushed function: BrowseArchiveButton
        function BrowseArchiveButtonPushed(app, event)
            startDir = app.archiveRoot;
            if isempty(startDir) || ~exist(startDir,'dir')
                startDir = pwd;
            end
            selectedDir = uigetdir(startDir, 'Select training archive directory');
            if isequal(selectedDir,0)
                return
            end
            app.archiveRoot = selectedDir;
            app.ArchiveDirectoryEditField.Value = selectedDir;
            % Create the expected archive subdirectories immediately.
            if ~exist(fullfile(selectedDir,'trainingImages'),'dir'); mkdir(fullfile(selectedDir,'trainingImages')); end
            if ~exist(fullfile(selectedDir,'trainingLabels'),'dir'); mkdir(fullfile(selectedDir,'trainingLabels')); end
            if ~exist(fullfile(selectedDir,'trainingMeta'),'dir'); mkdir(fullfile(selectedDir,'trainingMeta')); end
        end

        % Button pushed function: SaveandContinueButton
        function SaveandContinueButtonPushed(app, event)
            save_continue(app)
            
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 640 480];
            app.UIFigure.Name = 'MATLAB App';

            % Create UIAxes
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, 'Title')
            xlabel(app.UIAxes, 'X')
            ylabel(app.UIAxes, 'Y')
            zlabel(app.UIAxes, 'Z')
            app.UIAxes.TickDir = 'out';
            app.UIAxes.Position = [295 54 300 354];

            % Create SelectFiles
            app.SelectFiles = uibutton(app.UIFigure, 'push');
            app.SelectFiles.ButtonPushedFcn = createCallbackFcn(app, @SelectFilesPushed, true);
            app.SelectFiles.Position = [104 397 111 22];
            app.SelectFiles.Text = 'Select Video Files';

            % Create TextAreaLabel
            app.TextAreaLabel = uilabel(app.UIFigure);
            app.TextAreaLabel.HorizontalAlignment = 'right';
            app.TextAreaLabel.Position = [37 237 55 22];
            app.TextAreaLabel.Text = 'Text Area';

            % Create TextArea
            app.TextArea = uitextarea(app.UIFigure);
            app.TextArea.Position = [107 201 150 60];

            % Create SelectDirectoryLabel
            app.SelectDirectoryLabel = uilabel(app.UIFigure);
            app.SelectDirectoryLabel.HorizontalAlignment = 'right';
            app.SelectDirectoryLabel.Position = [42 367 94 22];
            app.SelectDirectoryLabel.Text = 'Select Directory:';

            % Create SelectCurrentDirectory
            app.SelectCurrentDirectory = uidropdown(app.UIFigure);
            app.SelectCurrentDirectory.Position = [151 367 100 22];

            % Create SelectFileLabel
            app.SelectFileLabel = uilabel(app.UIFigure);
            app.SelectFileLabel.HorizontalAlignment = 'right';
            app.SelectFileLabel.Position = [74 335 64 22];
            app.SelectFileLabel.Text = 'Select File:';

            % Create SelectCurrentFilename
            app.SelectCurrentFilename = uidropdown(app.UIFigure);
            app.SelectCurrentFilename.DropDownOpeningFcn = createCallbackFcn(app, @SelectCurrentFilenameDropDownOpening, true);
            app.SelectCurrentFilename.ValueChangedFcn = createCallbackFcn(app, @SelectCurrentFilenameValueChanged, true);
            app.SelectCurrentFilename.Position = [153 335 100 22];

            % Create StartFrameEditFieldLabel
            app.StartFrameEditFieldLabel = uilabel(app.UIFigure);
            app.StartFrameEditFieldLabel.HorizontalAlignment = 'right';
            app.StartFrameEditFieldLabel.Position = [16 305 69 22];
            app.StartFrameEditFieldLabel.Text = 'Start Frame';

            % Create StartFrameEditField
            app.StartFrameEditField = uieditfield(app.UIFigure, 'numeric');
            app.StartFrameEditField.Limits = [1 Inf];
            app.StartFrameEditField.RoundFractionalValues = 'on';
            app.StartFrameEditField.Position = [100 305 20 22];
            app.StartFrameEditField.Value = 1;

            % Create LoadVideoButton
            app.LoadVideoButton = uibutton(app.UIFigure, 'push');
            app.LoadVideoButton.ButtonPushedFcn = createCallbackFcn(app, @LoadVideoButtonPushed, true);
            app.LoadVideoButton.Position = [123 271 100 22];
            app.LoadVideoButton.Text = 'Load Video';

            % Create FramestoPlotEditFieldLabel
            app.FramestoPlotEditFieldLabel = uilabel(app.UIFigure);
            app.FramestoPlotEditFieldLabel.HorizontalAlignment = 'right';
            app.FramestoPlotEditFieldLabel.Position = [122 303 91 22];
            app.FramestoPlotEditFieldLabel.Text = '#Frames to Plot';

            % Create FramestoPlotEditField
            app.FramestoPlotEditField = uieditfield(app.UIFigure, 'numeric');
            app.FramestoPlotEditField.Limits = [1 1000];
            app.FramestoPlotEditField.Position = [228 303 36 21];
            app.FramestoPlotEditField.Value = 10;

            % Create SelectFrontButton
            app.SelectFrontButton = uibutton(app.UIFigure, 'push');
            app.SelectFrontButton.ButtonPushedFcn = createCallbackFcn(app, @SelectFrontButtonPushed, true);
            app.SelectFrontButton.Position = [17 134 143 52];
            app.SelectFrontButton.Text = 'Select Front';

            % Create ProcessAllFramesButton
            app.ProcessAllFramesButton = uibutton(app.UIFigure, 'push');
            app.ProcessAllFramesButton.ButtonPushedFcn = createCallbackFcn(app, @ProcessAllFramesButtonPushed, true);
            app.ProcessAllFramesButton.Position = [17 82 143 43];
            app.ProcessAllFramesButton.Text = 'Process All Frames';

            % Create RemoveFrontButton
            app.RemoveFrontButton = uibutton(app.UIFigure, 'push');
            app.RemoveFrontButton.ButtonPushedFcn = createCallbackFcn(app, @RemoveFrontButtonPushed, true);
            app.RemoveFrontButton.Position = [174 149 100 22];
            app.RemoveFrontButton.Text = 'Remove Front';

            % Create SaveandContinueButton
            app.SaveandContinueButton = uibutton(app.UIFigure, 'push');
            app.SaveandContinueButton.ButtonPushedFcn = createCallbackFcn(app, @SaveandContinueButtonPushed, true);
            app.SaveandContinueButton.Position = [174 82 143 43];
            app.SaveandContinueButton.Text = 'Save and Continue';

            % Create CameraIDEditFieldLabel
            app.CameraIDEditFieldLabel = uilabel(app.UIFigure);
            app.CameraIDEditFieldLabel.HorizontalAlignment = 'right';
            app.CameraIDEditFieldLabel.Position = [20 438 90 22];
            app.CameraIDEditFieldLabel.Text = 'Camera ID:';

            % Create CameraIDEditField
            app.CameraIDEditField = uieditfield(app.UIFigure, 'text');
            app.CameraIDEditField.Position = [120 438 100 22];
            app.CameraIDEditField.Placeholder = 'e.g. top21';

            % Create ArchiveDirectoryEditFieldLabel
            app.ArchiveDirectoryEditFieldLabel = uilabel(app.UIFigure);
            app.ArchiveDirectoryEditFieldLabel.HorizontalAlignment = 'right';
            app.ArchiveDirectoryEditFieldLabel.Position = [10 20 110 22];
            app.ArchiveDirectoryEditFieldLabel.Text = 'Training archive:';

            % Create ArchiveDirectoryEditField
            app.ArchiveDirectoryEditField = uieditfield(app.UIFigure, 'text');
            app.ArchiveDirectoryEditField.Position = [125 20 390 22];
            app.ArchiveDirectoryEditField.Value = '';
            app.ArchiveDirectoryEditField.Tooltip = {'Parent directory for trainingImages, trainingLabels, and trainingMeta'};

            % Create BrowseArchiveButton
            app.BrowseArchiveButton = uibutton(app.UIFigure, 'push');
            app.BrowseArchiveButton.ButtonPushedFcn = createCallbackFcn(app, @BrowseArchiveButtonPushed, true);
            app.BrowseArchiveButton.Position = [525 20 90 22];
            app.BrowseArchiveButton.Text = 'Browse...';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = select_CNN_training_ID_archive

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end