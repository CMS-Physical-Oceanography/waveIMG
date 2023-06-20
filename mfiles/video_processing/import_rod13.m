% top folder yyyymmdd and subfolder HHMM
% OCMdandt = {'20130929', {'1100','1200','1300','1400'}};
%[folder] = uigetdirs()
%asks for input of data
%folder = input('Enter the name of the file where all the video data is in: ', 's')
%date = input('Enter the date of the file in yyyymmdd format: ', 's')
%time = inputdlg('Enter a list "[]" of the times in military format: 
 
newPath ='empty';
fullPath = {};
while ~ isempty(newPath)
    newPath = uigetdirs();
    fullPath = cat(2,fullPath,newPath);
end
fullPath = fullPath'

%OCMdandt = {date, time}

% get a tally of the number of subfolders in each top folder

%
%tag = cell(OCMnumfiles,1);
%importDir = cell(OCMnumfiles,1);
%workingDir = cell(OCMnumfiles,1);
%cnt = 1;
%for i = 1:size(OCMdandt, 1)
    %d = OCMdandt{i, 1};
    %t = OCMdandt{i, 2};
    for ii = 1:length(fullPath)
        tag{ii} = ['testing_',num2str(ii)]; %tag incriment
        importDir{ii} = string(fullPath{ii}) %have to convert each path to string for rectify
        workingDir{ii} = [fullPath{ii},filesep,'..',filesep]
    end
    %for j = 1:length(t)
        %tag{cnt} = ['ROD13_' d '_' t{j}];
        % CHANGE TO YOUR IMPORT DIRECTORY
        %importDir{cnt} = [folder,filesep, d filesep t{j}]; 
        % CHANGE TO WHEREVER YOU WANT THE DATA TO SAVE
        %workingDir{cnt}= [folder,filesep, d]; 
        %cnt = cnt + 1;
    %end
%end

expID = 'rod13';
for k = 1:length(fullPath)
    [ocean,oceanSum,oceanX,oceanY,infoOCM] = rectify_vd(tag{k},workingDir{k},importDir{k},expID);
end

